import Foundation

enum ProxyType: String, Codable, CaseIterable, Identifiable {
    case auto = "AUTO"
    case https = "HTTPS"
    case http = "HTTP"
    case socks5 = "SOCKS5"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Авто"
        case .https: return "HTTPS-proxy (TLS)"
        case .http: return "HTTP/HTTPS (CONNECT)"
        case .socks5: return "SOCKS5"
        }
    }
}

enum PrimaryRestorePolicy: String, Codable {
    case stayOnCurrent = "STAY_ON_CURRENT"
    case returnToPrimary = "RETURN_TO_PRIMARY"
}

struct ProxyProfile: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var type: ProxyType
    var username: String?

    init(id: UUID = UUID(), name: String, host: String, port: Int, type: ProxyType, username: String? = nil) {
        precondition(!host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        precondition((1...65535).contains(port))
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.type = type
        self.username = username?.isEmpty == true ? nil : username
    }
}
