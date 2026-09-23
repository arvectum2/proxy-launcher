import Foundation
import Network

enum ProxyConfigurationError: Error {
    case missingProviderConfiguration
    case missingHost
    case invalidPort
}

struct UpstreamProxyConfiguration: Equatable {
    static let hostKey = "upstreamHost"
    static let portKey = "upstreamPort"
    static let usernameKey = "upstreamUsername"
    static let passwordKey = "upstreamPassword"

    let host: String
    let port: UInt16
    let username: String?
    let password: String?

    init(providerConfiguration: [String: Any]?) throws {
        guard let providerConfiguration else {
            throw ProxyConfigurationError.missingProviderConfiguration
        }
        guard let host = providerConfiguration[Self.hostKey] as? String,
              !host.isEmpty else {
            throw ProxyConfigurationError.missingHost
        }
        let rawPort = providerConfiguration[Self.portKey]
        let port: UInt16?
        if let value = rawPort as? NSNumber {
            port = UInt16(exactly: value.intValue)
        } else if let value = rawPort as? String,
                  let parsed = UInt16(value) {
            port = parsed
        } else {
            port = nil
        }
        guard let port, port > 0 else {
            throw ProxyConfigurationError.invalidPort
        }

        self.host = host
        self.port = port
        self.username = providerConfiguration[Self.usernameKey] as? String
        self.password = providerConfiguration[Self.passwordKey] as? String
    }

    var nwHost: NWEndpoint.Host { NWEndpoint.Host(host) }

    var nwPort: NWEndpoint.Port {
        NWEndpoint.Port(rawValue: port)!
    }

    var proxyAuthorizationHeader: String? {
        guard let username, let password else { return nil }
        let raw = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(raw)"
    }
}
