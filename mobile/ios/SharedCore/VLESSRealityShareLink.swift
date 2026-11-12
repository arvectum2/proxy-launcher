import Foundation

/// A validated, *inactive* VLESS/REALITY import candidate. The production
/// tun2proxy engine supports only HTTP/HTTPS/SOCKS5; this data object cannot
/// activate, persist or mislabel an unsupported transport.
struct VLESSRealityShareLink: Equatable {
    let name: String
    let serverHost: String
    let serverPort: Int
    let userID: UUID
    let serverName: String
    let fingerprint: String
    let publicKey: Data
    let shortID: String
    let visionFlow: Bool
    private let originalLink: String

    enum Failure: Error, Equatable {
        case unsupported, invalid, oversized
    }

    static let maxSourceBytes = 4_096
    private static let allowedKeys: Set<String> = [
        "encryption", "security", "type", "sni", "pbk", "sid", "fp", "flow"
    ]

    static func parse(_ text: String) throws -> VLESSRealityShareLink {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, source.utf8.count <= maxSourceBytes else {
            throw Failure.oversized
        }
        guard !source.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URLComponents(string: source),
              url.scheme?.lowercased() == "vless",
              url.password == nil,
              let uid = url.user, let userID = UUID(uuidString: uid),
              let host = url.host, !host.isEmpty, host.utf8.count <= 253,
              !host.contains(where: { $0.isWhitespace || $0.isNewline }),
              let port = url.port, (1...65_535).contains(port),
              url.path.isEmpty || url.path == "/",
              let entries = url.queryItems, !entries.isEmpty
        else { throw Failure.invalid }

        var fields: [String: String] = [:]
        for entry in entries {
            guard entry.name == entry.name.lowercased(),
                  allowedKeys.contains(entry.name),
                  let value = entry.value,
                  fields.updateValue(value, forKey: entry.name) == nil else {
                throw Failure.unsupported
            }
        }
        guard fields["encryption"] == "none", fields["security"] == "reality",
              fields["type"] == "tcp",
              let sni = fields["sni"]?.lowercased(),
              ManagedProfileContract.validDNS(sni),
              let fingerprint = fields["fp"]?.lowercased(),
              ["chrome", "firefox", "safari", "ios"].contains(fingerprint),
              let keyString = fields["pbk"],
              let key = publicKeyBytes(keyString)
        else { throw Failure.unsupported }

        let shortID = fields["sid"] ?? ""
        guard shortID.utf8.count <= 16, shortID.count.isMultiple(of: 2),
              shortID.utf8.allSatisfy({
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
              }),
              fields["flow"] == nil || fields["flow"] == "" ||
                fields["flow"] == "xtls-rprx-vision"
        else { throw Failure.unsupported }

        let caption = (url.fragment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard caption.utf8.count <= 80,
              !caption.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw Failure.invalid }
        return VLESSRealityShareLink(
            name: caption.isEmpty ? "\(host):\(port)" : caption,
            serverHost: host, serverPort: port, userID: userID, serverName: sni,
            fingerprint: fingerprint, publicKey: key, shortID: shortID,
            visionFlow: fields["flow"] == "xtls-rprx-vision", originalLink: source
        )
    }

    /// Data-only request for the pinned libXray v26.11.9 CGoInvoke API v3.
    /// No Xray runtime is bundled or called by this source-only contract.
    /// The original URI is treated as sensitive and must never be logged.
    func conversionRequest() throws -> Data {
        struct Payload: Encodable { let text: String }
        struct Request: Encodable {
            let apiVersion: Int
            let method: String
            let payload: Payload
        }
        return try JSONEncoder().encode(Request(
            apiVersion: 3, method: "convertShareLinksToXrayJson",
            payload: Payload(text: originalLink)
        ))
    }

    private static func publicKeyBytes(_ raw: String) -> Data? {
        guard (40...48).contains(raw.utf8.count),
              raw.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) ||
                (48...57).contains($0) || $0 == 45 || $0 == 95
              }) else { return nil }
        let standard = raw.replacingOccurrences(of: "-", with: "+")
                          .replacingOccurrences(of: "_", with: "/")
        let padded = standard + String(repeating: "=", count: (4 - standard.count % 4) % 4)
        guard let bytes = Data(base64Encoded: padded), bytes.count == 32 else { return nil }
        return bytes
    }
}
