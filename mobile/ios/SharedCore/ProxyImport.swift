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
