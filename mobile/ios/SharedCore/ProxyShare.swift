import Foundation

enum ProxyShareError: LocalizedError {
    case invalid
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalid: return "Cannot share this proxy profile."
        case .tooLarge: return "The proxy profile is too large for a scannable QR code."
        }
    }
}

/// Offline credential-bearing QR format: one versioned profile per link.
/// Never record this payload to UserDefaults, analytics, logs or clipboard.
enum ProxyShare {
    static let prefix = "apl1."
    static let maxLinkBytes = 1_400

    private struct Wire: Codable {
        let version: Int
        let name: String
        let host: String
        let port: Int
        let type: ProxyType
        let username: String
        let password: String
    }

    static func makeDeepLink(profile: ProxyProfile, password: String?) throws -> URL {
        let wire = Wire(version: 1, name: profile.name, host: profile.host,
                        port: profile.port, type: profile.type,
                        username: profile.username ?? "", password: password ?? "")
        try validate(wire)
        // Fail before rendering if the source host/port is not importable.
        _ = try ProxyImport.item(host: wire.host, port: String(wire.port),
                                 username: wire.username, password: wire.password,
                                 type: wire.type == .auto ? .http : wire.type,
                                 name: wire.name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(wire)
        let payload = prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = "arvectum-proxy"
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "data", value: payload)]
        guard let url = components.url, url.absoluteString.utf8.count <= maxLinkBytes else {
            throw ProxyShareError.tooLarge
        }
        return url
    }

    static func decode(_ payload: String) throws -> ImportedProxy {
        guard payload.hasPrefix(prefix) else { throw ProxyShareError.invalid }
        let part = String(payload.dropFirst(prefix.count))
        guard !part.isEmpty, part.utf8.count <= maxLinkBytes,
              part.utf8.allSatisfy({
                  (48...57).contains($0) || (65...90).contains($0) ||
                  (97...122).contains($0) || $0 == 45 || $0 == 95
              }) else { throw ProxyShareError.invalid }
        let padded = part.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") +
            String(repeating: "=", count: (4 - part.count % 4) % 4)
        guard let data = Data(base64Encoded: padded),
              let wire = try? JSONDecoder().decode(Wire.self, from: data) else {
            throw ProxyShareError.invalid
        }
        try validate(wire)
        // Validate authority with the existing strict importer. AUTO is an
        // explicit saved profile type, not a protocol inferred from an address.
        let verified = try ProxyImport.item(host: wire.host, port: String(wire.port),
                                           username: wire.username, password: wire.password,
                                           type: wire.type == .auto ? .http : wire.type,
                                           name: wire.name)
        return ImportedProxy(name: verified.name, host: verified.host,
                             port: verified.port, type: wire.type,
                             username: wire.username, password: wire.password)
    }

    private static func validate(_ wire: Wire) throws {
        guard wire.version == 1, !wire.name.isEmpty,
              wire.name.utf8.count <= 180,
              wire.host.utf8.count <= 255,
              (1...65_535).contains(wire.port),
              wire.username.utf8.count <= 256,
              wire.password.utf8.count <= 1_024,
              !wire.name.contains("\0"),
              !wire.username.contains("\0"),
              !wire.password.contains("\0") else {
            throw ProxyShareError.invalid
        }
    }
}
