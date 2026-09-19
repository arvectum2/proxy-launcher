import Foundation
import Network

struct ProxyProbeResult {
    let profile: ProxyProfile
    let latencyMs: Int
}

enum ProxyProbeError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        if case .unavailable(let detail) = self { return detail }
        return nil
    }
}

final class ProxyProbe {
    private let queue = DispatchQueue(label: "ru.arvectum.proxylauncher.ios.probe")
    private let probeHost = "example.com"
    private let probePort: UInt16 = 443

    func resolveMeasured(_ profile: ProxyProfile, password: String?) async throws -> ProxyProbeResult {
        let candidates: [ProxyType] = profile.type == .auto ? [.http, .socks5, .https] : [profile.type]
        var failures: [String] = []
        for candidate in candidates {
            let started = DispatchTime.now().uptimeNanoseconds
            do {
                switch candidate {
                case .http: try await probeHTTP(profile, password: password, tls: false)
                case .https: try await probeHTTP(profile, password: password, tls: true)
                case .socks5: try await probeSOCKS5(profile, password: password)
                case .auto: continue
                }
                let elapsed = max(1, Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000))
                var resolved = profile
                resolved.type = candidate
                return ProxyProbeResult(profile: resolved, latencyMs: elapsed)
            } catch {
                failures.append("\(candidate.label): \(error.localizedDescription)")
            }
        }
        throw ProxyProbeError.unavailable("Не удалось подобрать протокол. " + failures.joined(separator: "; "))
    }

    private func probeHTTP(_ profile: ProxyProfile, password: String?, tls: Bool) async throws {
        let parameters = tls ? NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options()) : .tcp
        let connection = NWConnection(host: NWEndpoint.Host(profile.host), port: NWEndpoint.Port(rawValue: UInt16(profile.port))!, using: parameters)
        try await start(connection)
        var request = "CONNECT \(probeHost):\(probePort) HTTP/1.1\r\nHost: \(probeHost):\(probePort)\r\nProxy-Connection: close\r\n"
        if let username = profile.username, !username.isEmpty {
            let token = Data("\(username):\(password ?? "")".utf8).base64EncodedString()
            request += "Proxy-Authorization: Basic \(token)\r\n"
        }
        request += "\r\n"
        try await send(Data(request.utf8), on: connection)
        var response = Data()
        while response.count < 8192, !response.containsHeaderTerminator {
            let chunk = try await receive(minimum: 1, maximum: 4096, on: connection)
            if chunk.isEmpty { break }
            response.append(chunk)
        }
        connection.cancel()
        guard let text = String(data: response, encoding: .isoLatin1),
              let firstLine = text.components(separatedBy: "\r\n").first,
              firstLine.hasPrefix("HTTP/"),
              let statusText = firstLine.split(separator: " ").dropFirst().first,
              let status = Int(statusText) else {
            throw ProxyProbeError.unavailable("ответ не похож на HTTP proxy")
        }
        if (200...299).contains(status) { return }
        if status == 407, profile.username?.isEmpty != false { throw ProxyProbeError.unavailable("прокси требует логин/пароль") }
        if status == 407, text.range(of: "Proxy-Authenticate: Digest", options: .caseInsensitive) != nil { return }
        if status == 407 { throw ProxyProbeError.unavailable("логин/пароль отклонены") }
        throw ProxyProbeError.unavailable("CONNECT вернул HTTP \(status)")
    }

    private func probeSOCKS5(_ profile: ProxyProfile, password: String?) async throws {
        let connection = NWConnection(host: NWEndpoint.Host(profile.host), port: NWEndpoint.Port(rawValue: UInt16(profile.port))!, using: .tcp)
        try await start(connection)
        let hasCredentials = !(profile.username ?? "").isEmpty
        try await send(Data(hasCredentials ? [0x05, 0x02, 0x00, 0x02] : [0x05, 0x01, 0x00]), on: connection)
        let greeting = try await receive(minimum: 2, maximum: 2, on: connection)
        guard greeting.count == 2, greeting[0] == 0x05 else {
            connection.cancel(); throw ProxyProbeError.unavailable("не SOCKS5")
        }
        if greeting[1] == 0x02 {
            guard let username = profile.username, !username.isEmpty else {
                connection.cancel(); throw ProxyProbeError.unavailable("прокси требует логин/пароль")
            }
            let user = Data(username.utf8), pass = Data((password ?? "").utf8)
            guard user.count <= 255, pass.count <= 255 else {
                connection.cancel(); throw ProxyProbeError.unavailable("слишком длинный логин/пароль")
            }
            var auth = Data([0x01, UInt8(user.count)])
            auth.append(user); auth.append(UInt8(pass.count)); auth.append(pass)
            try await send(auth, on: connection)
            let result = try await receive(minimum: 2, maximum: 2, on: connection)
            guard result.count == 2, result[1] == 0x00 else {
                connection.cancel(); throw ProxyProbeError.unavailable("логин/пароль отклонены")
            }
        } else if greeting[1] == 0xff {
            connection.cancel(); throw ProxyProbeError.unavailable("нет совместимого способа авторизации")
        }
        let domain = Data(probeHost.utf8)
        var request = Data([0x05, 0x01, 0x00, 0x03, UInt8(domain.count)])
        request.append(domain); request.append(UInt8((probePort >> 8) & 0xff)); request.append(UInt8(probePort & 0xff))
        try await send(request, on: connection)
        let reply = try await receive(minimum: 4, maximum: 4, on: connection)
        guard reply.count == 4, reply[0] == 0x05, reply[1] == 0x00 else {
            connection.cancel(); throw ProxyProbeError.unavailable("CONNECT отклонён")
        }
        let tail: Int
        switch reply[3] {
        case 0x01: tail = 6
        case 0x04: tail = 18
        case 0x03:
            let length = try await receive(minimum: 1, maximum: 1, on: connection)
            tail = Int(length.first ?? 0) + 2
        default:
            connection.cancel(); throw ProxyProbeError.unavailable("неизвестный тип SOCKS5-адреса")
        }
        _ = try await receive(minimum: tail, maximum: tail, on: connection)
        connection.cancel()
    }

    private func start(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            connection.stateUpdateHandler = { state in
                lock.lock(); defer { lock.unlock() }
                guard !resumed else { return }
                switch state {
                case .ready: resumed = true; continuation.resume()
                case .failed(let error): resumed = true; continuation.resume(throwing: error)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) {
                lock.lock(); defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true; connection.cancel()
                continuation.resume(throwing: ProxyProbeError.unavailable("таймаут"))
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private func receive(minimum: Int, maximum: Int, on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: minimum, maximumLength: maximum) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data ?? Data()) }
            }
        }
    }
}

private extension Data {
    var containsHeaderTerminator: Bool { range(of: Data([13, 10, 13, 10])) != nil }
}
