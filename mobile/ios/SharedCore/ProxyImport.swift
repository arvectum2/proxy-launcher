import Foundation

struct ImportedProxy: Equatable {
    let name: String
    let host: String
    let port: Int
    let type: ProxyType
    let username: String
    let password: String
}

enum ProxyImportError: LocalizedError {
    case unsupported, invalid, tooLarge, empty
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Поддерживаются ссылки HTTP/HTTPS/SOCKS5 и IP:порт:логин:пароль"
        case .invalid: return "Некорректный адрес, порт или формат списка прокси"
        case .tooLarge: return "Слишком большой файл или список прокси"
        case .empty: return "Не найдены ссылки на прокси"
        }
    }
}

enum ProxyImport {
    static func fromDeepLink(_ url: URL) throws -> String {
        guard url.scheme?.lowercased() == "arvectum-proxy", url.host?.lowercased() == "import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let values = components.queryItems?.filter({ $0.name == "data" }),
              values.count == 1, let value = values.first?.value else { throw ProxyImportError.invalid }
        _ = try parse(value)
        return value
    }

    static func withoutDuplicates(_ items: [ImportedProxy], existing: [ProxyProfile]) -> [ImportedProxy] {
        var keys = Set(existing.map { "\($0.type.rawValue)|\($0.host.lowercased())|\($0.port)|\($0.username ?? "")" })
        return items.filter { item in
            keys.insert("\(item.type.rawValue)|\(item.host.lowercased())|\(item.port)|\(item.username)").inserted
        }
    }

    /// The selected type applies only when the supplier omitted a protocol.
    /// Parsing is all-or-nothing, with bounded input and no credential logging.
    static func parse(_ input: String, defaultType: ProxyType = .http) throws -> [ImportedProxy] {
        guard input.utf8.count <= 256_000 else { throw ProxyImportError.tooLarge }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = trimmed.hasPrefix("\u{FEFF}") ? String(trimmed.dropFirst()) : trimmed
        guard !clean.isEmpty else { throw ProxyImportError.empty }
        let fallback = defaultType == .auto ? ProxyType.http : defaultType
        let result: [ImportedProxy]
        if clean.first == "<" {
            result = try ProxyImportStructured.xml(clean, defaultType: fallback)
        } else if ProxyImportStructured.looksLikeCSV(clean) {
            result = try ProxyImportStructured.csv(clean, defaultType: fallback)
        } else {
            let lines = clean.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            guard !lines.isEmpty else { throw ProxyImportError.empty }
            guard lines.count <= 200 else { throw ProxyImportError.tooLarge }
            result = try lines.map { try parseLine($0, defaultType: fallback) }
        }
        guard !result.isEmpty else { throw ProxyImportError.empty }
        guard result.count <= 200 else { throw ProxyImportError.tooLarge }
        return result
    }

    static func specifiedType(_ value: String?, defaultType: ProxyType) throws -> ProxyType {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "": return defaultType
        case "http": return .http
        case "https": return .https
        case "socks5", "socks5h", "socks": return .socks5
        default: throw ProxyImportError.unsupported
        }
    }

    static func item(host: String, port: String, username: String = "",
                     password: String = "", type: ProxyType, name: String = "") throws -> ImportedProxy {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(number), !target.isEmpty,
              !target.contains(where: { $0.isWhitespace || $0.isNewline }),
              !target.contains("/") && !target.contains("@") && !target.contains("?") && !target.contains("#"),
              type != .auto else { throw ProxyImportError.invalid }
        let authority = target.contains(":") && !target.hasPrefix("[") ? "[\(target)]" : target
        guard let components = URLComponents(string: "http://\(authority):\(number)"),
              let parsedHost = components.host, !parsedHost.isEmpty,
              components.port == number, components.user == nil,
              components.password == nil, components.query == nil,
              components.path.isEmpty else { throw ProxyImportError.invalid }
        let caption = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ImportedProxy(name: caption.isEmpty ? "\(parsedHost):\(number)" : caption,
                             host: parsedHost, port: number, type: type,
                             username: username, password: password)
    }

    private static func parseLine(_ text: String, defaultType: ProxyType) throws -> ImportedProxy {
        if text.contains("://") {
            guard let url = URLComponents(string: text), let scheme = url.scheme else {
                throw ProxyImportError.invalid
            }
            let type = try specifiedType(scheme, defaultType: defaultType)
            guard let host = url.host, let port = url.port,
                  url.path.isEmpty || url.path == "/", url.query == nil else {
                throw ProxyImportError.invalid
            }
            return try item(host: host, port: String(port),
                            username: url.user?.removingPercentEncoding ?? "",
                            password: url.password?.removingPercentEncoding ?? "",
                            type: type, name: url.fragment?.removingPercentEncoding ?? "")
        }
        // Supplier notation host:port[:user:password]. Split only 3 colons:
        // password may contain colons. Bracketed IPv6 is also supported.
        let host: String
        let remainder: String
        if text.first == "[", let end = text.firstIndex(of: "]"),
           text.index(after: end) < text.endIndex,
           text[text.index(after: end)] == ":" {
            host = String(text[...end])
            remainder = String(text[text.index(end, offsetBy: 2)...])
        } else {
            let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw ProxyImportError.invalid }
            host = String(parts[0]); remainder = String(parts[1])
        }
        let parts = remainder.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 1 || parts.count == 3 else { throw ProxyImportError.invalid }
        return try item(host: host, port: parts[0],
                        username: parts.count == 3 ? parts[1] : "",
                        password: parts.count == 3 ? parts[2] : "",
                        type: defaultType)
    }
}
