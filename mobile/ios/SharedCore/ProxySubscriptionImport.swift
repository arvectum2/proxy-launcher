import Foundation

/// Explicit, user-initiated subscription download. No background polling,
/// implicit profile replacement, persistent URL/token or VPN mutation.
enum ProxySubscriptionError: Error, Equatable {
    case unsafeSource, oversized, invalidBody, unsupportedBody
}

enum ProxySubscriptionImport {
    static let maxBytes = 256_000
    static let maxURLLength = 2_048

    static func sourceURL(_ text: String) throws -> URL {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.utf8.count <= maxURLLength,
              let parts = URLComponents(string: raw),
              parts.scheme?.lowercased() == "https",
              let host = parts.host?.lowercased(),
              ManagedProfileContract.validDNS(host),
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.port == nil || parts.port == 443,
              !["localhost", "local", "internal", "lan", "home", "test", "invalid", "onion"]
                .contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = parts.url, url.scheme?.lowercased() == "https"
        else { throw ProxySubscriptionError.unsafeSource }
        // A provider's query token may be required; never log the URL.
        return url
    }

    /// Accept only formats already understood by the live HTTP/SOCKS engine.
    /// A base64-encoded list is common with proxy suppliers; never discard
    /// unsupported VLESS/WireGuard rows and silently import a subset.
    static func decode(_ bytes: Data, defaultType: ProxyType = .http) throws -> String {
        guard bytes.count <= maxBytes else { throw ProxySubscriptionError.oversized }
        guard let text = String(data: bytes, encoding: .utf8), !text.contains("\0") else {
            throw ProxySubscriptionError.invalidBody
        }
        if (try? ProxyImport.parse(text, defaultType: defaultType)) != nil { return text }

        let compact = text.filter { !$0.isWhitespace }
        guard !compact.isEmpty, compact.count <= maxBytes,
              compact.utf8.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) ||
                                        ($0 >= 48 && $0 <= 57) || $0 == 43 || $0 == 47 || $0 == 61 }),
              let decoded = Data(base64Encoded: compact),
              decoded.count <= maxBytes,
              let payload = String(data: decoded, encoding: .utf8),
              !payload.contains("\0") else { throw ProxySubscriptionError.unsupportedBody }
        do {
            _ = try ProxyImport.parse(payload, defaultType: defaultType)
        } catch { throw ProxySubscriptionError.unsupportedBody }
        return payload
    }
}
