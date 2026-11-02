import Foundation

/// Before the tunnel starts, atomically replace a gateway account's exact
/// hostname policy using verified HTTPS and the selected profile's Keychain
/// token. No raw proxy password, policy, host or IP is logged.
enum SmartGatewayPolicySync {
    private struct Body: Encodable { let domains: [String] }
    private struct Receipt: Decodable { let ok: Bool; let count: Int }

    static func push(
        profile: ProxyProfile,
        password: String?,
        effectiveExclusions: [String]
    ) async throws {
        guard profile.type == .gateway,
              let username = profile.username, !username.isEmpty,
              let password, !password.isEmpty else {
            throw NSError(domain: "ArvectumSmartGateway", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "APL Gateway требует логин и токен"])
        }
        let domains = SmartGatewayExclusionPolicy.approvedHosts(from: effectiveExclusions)
        guard domains.count <= 128 else {
            throw NSError(domain: "ArvectumSmartGateway", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Слишком много доменов для шлюза"])
        }
        var url = URLComponents()
        url.scheme = "https"
        url.host = profile.host
        url.port = profile.port
        url.path = "/v1/smart/policy"
        guard let destination = url.url else {
            throw NSError(domain: "ArvectumSmartGateway", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Неверный адрес шлюза"])
        }
        var request = URLRequest(url: destination)
        request.httpMethod = "PUT"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credential = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Body(domains: domains))
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 12
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
              receipt.ok && receipt.count == domains.count else {
            throw NSError(domain: "ArvectumSmartGateway", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Не удалось применить исключения на шлюзе"])
        }
    }
}
