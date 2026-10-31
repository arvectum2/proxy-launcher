import Foundation
import Network

struct ProxyProbeResult {
    let profile: ProxyProfile
    let latencyMs: Int
}

/// Network.framework may complete the connection or fire a timeout on
/// different queues. This gate resumes the Swift continuation exactly once.
private final class ProbeCompletionGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Value, Error>

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func finish(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        let shouldResume = !finished
        if shouldResume { finished = true }
        lock.unlock()
        guard shouldResume else { return false }
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
        return true
    }
}

final class ProxyProbe {
    private let queue = DispatchQueue(label: "ru.arvectum.proxylauncher.ios.probe")
    private let probeHost = "example.com"
    private let probePort: UInt16 = 443

    func resolveMeasured(_ profile: ProxyProfile, password: String?) async throws -> ProxyProbeResult {
        let candidates: [ProxyType] = profile.type == .auto ? [.http, .socks5, .https] : [profile.type]
        var failures: [ProxyFailureReason] = []
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
                failures.append(Self.failureReason(for: error))
            }
        }
        throw ProxyDiagnosticError(ProxyFailureReason.mostRelevant(failures))
    }

    /// Interpret typed Network.framework errors without logging their details.
    private static func failureReason(for error: Error) -> ProxyFailureReason {
        if let nw = error as? NWError {
            switch nw {
            case .dns: return .dns
            case .tls: return .tls
            case .posix(let code):
                return ProxyFailureReason.classify(NSError(domain: NSPOSIXErrorDomain, code: Int(code.rawValue)))
            default: return .unknown
            }
        }
        return ProxyFailureReason.classify(error)
    }

    private func probeHTTP(_ profile: ProxyProfile, password: String?, tls: Bool) async throws {
        let parameters = tls ? NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options()) : .tcp
        let connection = NWConnection(host: NWEndpoint.Host(profile.host), port: NWEndpoint.Port(rawValue: UInt16(profile.port))!, using: parameters)
        defer { connection.cancel() }
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
        // A partial HTTP status line without terminating headers is not a
        // verified CONNECT tunnel, even if it begins with 'HTTP/1.1 200'.
        guard response.containsHeaderTerminator,
              let text = String(data: response, encoding: .isoLatin1),
              let firstLine = text.components(separatedBy: "\r\n").first,
              firstLine.hasPrefix("HTTP/"),
              let statusText = firstLine.split(separator: " ").dropFirst().first,
              let status = Int(statusText) else {
            throw ProxyDiagnosticError(.protocolMismatch)
        }
        // Even a Digest 407 is only an authentication challenge, not a
        // successful tunnel; never mark an unverified proxy as available.
        if let reason = ProxyFailureReason.forHTTPConnectStatus(status) {
            throw ProxyDiagnosticError(reason)
        }
    }

    private func probeSOCKS5(_ profile: ProxyProfile, password: String?) async throws {
        let connection = NWConnection(host: NWEndpoint.Host(profile.host), port: NWEndpoint.Port(rawValue: UInt16(profile.port))!, using: .tcp)
        defer { connection.cancel() }
        try await start(connection)
        let hasCredentials = !(profile.username ?? "").isEmpty
        try await send(Data(hasCredentials ? [0x05, 0x02, 0x00, 0x02] : [0x05, 0x01, 0x00]), on: connection)
        let greeting = try await receive(minimum: 2, maximum: 2, on: connection)
        guard greeting.count == 2, greeting[0] == 0x05 else {
            throw ProxyDiagnosticError(.protocolMismatch)
        }
        if greeting[1] == 0x02 {
            guard let username = profile.username, !username.isEmpty else {
                throw ProxyDiagnosticError(.authentication)
            }
            let user = Data(username.utf8), pass = Data((password ?? "").utf8)
            guard user.count <= 255, pass.count <= 255 else {
                throw ProxyDiagnosticError(.authentication)
            }
            var auth = Data([0x01, UInt8(user.count)])
            auth.append(user); auth.append(UInt8(pass.count)); auth.append(pass)
            try await send(auth, on: connection)
            let result = try await receive(minimum: 2, maximum: 2, on: connection)
            guard result.count == 2, result[1] == 0x00 else {
                throw ProxyDiagnosticError(.authentication)
            }
        } else if greeting[1] != 0x00 {
            // SOCKS5 permits only a method the client offered. Other values
            // must fail closed; do not attempt an unauthenticated CONNECT.
            throw ProxyDiagnosticError(.protocolMismatch)
        }
        let domain = Data(probeHost.utf8)
        var request = Data([0x05, 0x01, 0x00, 0x03, UInt8(domain.count)])
        request.append(domain); request.append(UInt8((probePort >> 8) & 0xff)); request.append(UInt8(probePort & 0xff))
        try await send(request, on: connection)
        let reply = try await receive(minimum: 4, maximum: 4, on: connection)
        guard reply.count == 4, reply[0] == 0x05, reply[1] == 0x00 else {
            throw ProxyDiagnosticError(.rejected)
        }
        let tail: Int
        switch reply[3] {
        case 0x01: tail = 6
        case 0x04: tail = 18
        case 0x03:
            let length = try await receive(minimum: 1, maximum: 1, on: connection)
            tail = Int(length.first ?? 0) + 2
        default:
            throw ProxyDiagnosticError(.protocolMismatch)
        }
        _ = try await receive(minimum: tail, maximum: tail, on: connection)
        connection.cancel()
    }

    private func start(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ProbeCompletionGate(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: gate.finish(.success(()))
                case .failed(let error): gate.finish(.failure(error))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) {
                if gate.finish(.failure(ProxyDiagnosticError(.timeout))) {
                    connection.cancel()
                }
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ProbeCompletionGate(continuation)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { gate.finish(.failure(error)) }
                else { gate.finish(.success(())) }
            })
            queue.asyncAfter(deadline: .now() + 5) {
                if gate.finish(.failure(ProxyDiagnosticError(.timeout))) { connection.cancel() }
            }
        }
    }

    private func receive(minimum: Int, maximum: Int, on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let gate = ProbeCompletionGate(continuation)
            connection.receive(minimumIncompleteLength: minimum, maximumLength: maximum) { data, _, _, error in
                if let error { gate.finish(.failure(error)) }
                else { gate.finish(.success(data ?? Data())) }
            }
            // An accepting but silent proxy must not hang the entire scan.
            queue.asyncAfter(deadline: .now() + 5) {
                if gate.finish(.failure(ProxyDiagnosticError(.timeout))) { connection.cancel() }
            }
        }
    }

}

private extension Data {
    var containsHeaderTerminator: Bool { range(of: Data([13, 10, 13, 10])) != nil }
}
