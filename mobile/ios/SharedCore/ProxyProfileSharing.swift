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
        // Encode userinfo and fragment with only RFC 3986 unreserved scalars.
        // URLComponents setters differ across Foundation versions for custom
        // SOCKS5 schemes and reserved username punctuation (e.g. colon).
        let authority = checked.host.contains(":") && !checked.host.hasPrefix("[")
            ? "[\(checked.host)]" : checked.host
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encoded(_ value: String) throws -> String {
            guard let output = value.addingPercentEncoding(withAllowedCharacters: unreserved)
            else { throw ProxyImportError.invalid }
            return output
        }
        let userInfo: String
        if !checked.username.isEmpty || !checked.password.isEmpty {
            userInfo = "\(try encoded(checked.username)):\(try encoded(checked.password))@"
        } else {
            userInfo = ""
        }
        let fragment = checked.name.isEmpty ? "" : "#\(try encoded(checked.name))"
        let proxyURL = "\(scheme)://\(userInfo)\(authority):\(checked.port)\(fragment)"

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
