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
        case .unsupported: return "Поддерживаются ссылки http://, https:// и socks5://"
        case .invalid: return "Некорректный адрес или порт прокси"
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

    static func parse(_ input: String) throws -> [ImportedProxy] {
        guard input.utf8.count <= 256_000 else { throw ProxyImportError.tooLarge }
        let lines = input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !lines.isEmpty else { throw ProxyImportError.empty }
        guard lines.count <= 200 else { throw ProxyImportError.tooLarge }
        return try lines.map(parseLine)
    }

    private static func parseLine(_ text: String) throws -> ImportedProxy {
        guard let url = URLComponents(string: text), let scheme = url.scheme?.lowercased() else {
            throw ProxyImportError.invalid
        }
        let type: ProxyType
        switch scheme {
        case "http": type = .http
        case "https": type = .https
        case "socks5", "socks5h": type = .socks5
        default: throw ProxyImportError.unsupported
        }
        guard let host = url.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }),
              let port = url.port, (1...65535).contains(port),
              url.path.isEmpty || url.path == "/",
              url.query == nil else { throw ProxyImportError.invalid }
        let name = url.fragment?.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ImportedProxy(name: name?.isEmpty == false ? name! : "\(host):\(port)",
                             host: host, port: port, type: type,
                             username: url.user?.removingPercentEncoding ?? "",
                             password: url.password?.removingPercentEncoding ?? "")
    }
}
