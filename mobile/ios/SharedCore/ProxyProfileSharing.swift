import Foundation

/// A user-authorized portable profile link. It contains plaintext credentials:
/// never persist, prefetch, log or create it before an explicit Share action.
enum ProxyProfileSharing {
    /// QR payload is a registered APL deep link. The same URL can be sent
    /// through Apple Share Sheet and scanned by the existing import screen.
    static func deepLink(profile: ProxyProfile, password: String?) throws -> URL {
        let scheme: String
        switch profile.type {
        case .http: scheme = "http"
        case .https: scheme = "https"
        case .socks5: scheme = "socks5"
        case .auto: throw ProxyImportError.unsupported
        }

        // Validate through the receiver's own parser before encoding. No
        // untrusted host can be turned into a custom app URL or QR payload.
        let checked = try ProxyImport.item(
            host: profile.host, port: String(profile.port),
            username: profile.username ?? "", password: password ?? "",
            type: profile.type, name: profile.name
        )
        // Construct the authority exactly as the receiver's strict parser
        // does. Foundation versions differ in whether the host getter
        // includes IPv6 brackets, and setting a bracketed host may encode
        // it a second time on older SDKs.
        let authority = checked.host.contains(":") && !checked.host.hasPrefix("[")
            ? "[\(checked.host)]" : checked.host
        guard var transport = URLComponents(
            string: "\(scheme)://\(authority):\(checked.port)") else {
            throw ProxyImportError.invalid
        }
        if !checked.username.isEmpty { transport.user = checked.username }
        if !checked.password.isEmpty { transport.password = checked.password }
        if !checked.name.isEmpty { transport.fragment = checked.name }
        guard let proxyURL = transport.string else { throw ProxyImportError.invalid }

        // Round-trip secrets and non-ASCII fields before producing a QR.
        let decoded = try ProxyImport.parse(proxyURL)
        guard decoded.count == 1 else { throw ProxyImportError.invalid }
        let restored = decoded[0]
        // IPv6 bracket decoration is not semantic data. Never relax checks
        // on the username/password/port/protocol/name themselves.
        func unbracket(_ host: String) -> String {
            host.hasPrefix("[") && host.hasSuffix("]")
                ? String(host.dropFirst().dropLast()) : host
        }
        guard unbracket(restored.host) == unbracket(checked.host),
              restored.port == checked.port,
              restored.type == checked.type,
              restored.name == checked.name,
              restored.username == checked.username,
              restored.password == checked.password else {
            throw ProxyImportError.invalid
        }

        var link = URLComponents()
        link.scheme = "arvectum-proxy"
        link.host = "import"
        link.queryItems = [URLQueryItem(name: "data", value: proxyURL)]
        guard let url = link.url,
              url.absoluteString.utf8.count <= 1800,
              try ProxyImport.fromDeepLink(url) == proxyURL else {
            throw ProxyImportError.tooLarge
        }
        return url
    }

    /// Raw QR text can be a supplier proxy URL, or our own import deep link.
    /// Unsupported custom schemes fail closed rather than being silently
    /// treated as an HTTP proxy. The receiving UI still requires Import.
    static func scannedSource(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("arvectum-proxy:") {
            guard let url = URL(string: trimmed) else { throw ProxyImportError.invalid }
            return try ProxyImport.fromDeepLink(url)
        }
        _ = try ProxyImport.parse(trimmed)
        return trimmed
    }
}
