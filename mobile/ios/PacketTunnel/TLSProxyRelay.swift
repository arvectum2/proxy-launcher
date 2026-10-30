import Foundation
import Network

/// A one-shot continuation gate safe across Network.framework callbacks.
private final class RelayStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}

final class TLSProxyRelay {
    private let upstreamHost: NWEndpoint.Host
    private let upstreamPort: NWEndpoint.Port
    private let queue = DispatchQueue(label: "ru.arvectum.proxylauncher.ios.tlsrelay")
    private var listener: NWListener?
    private var connections: [UUID: (local: NWConnection, upstream: NWConnection)] = [:]

    init(host: String, port: Int) {
        upstreamHost = NWEndpoint.Host(host)
        upstreamPort = NWEndpoint.Port(rawValue: UInt16(port))!
    }

    func start() async throws -> Int {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: 0)!)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] local in
            self?.handle(local)
        }
        try await withCheckedThrowingContinuation { continuation in
            let gate = RelayStartGate()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if gate.claim() { continuation.resume() }
                case .failed(let error):
                    if gate.claim() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        guard let port = listener.port?.rawValue else {
            throw NSError(domain: "ArvectumTLSRelay", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Не удалось открыть локальный TLS relay"
            ])
        }
        return Int(port)
    }

    func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            guard let self else { return }
            for id in Array(self.connections.keys) { self.close(id) }
        }
    }


    /// All mutations occur on the serial Network.framework callback queue.
    private func close(_ id: UUID) {
        guard let pair = connections.removeValue(forKey: id) else { return }
        pair.local.stateUpdateHandler = nil
        pair.upstream.stateUpdateHandler = nil
        pair.local.cancel()
        pair.upstream.cancel()
    }

    private func handle(_ local: NWConnection) {
        let tls = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let upstream = NWConnection(host: upstreamHost, port: upstreamPort, using: parameters)
        let id = UUID()
        connections[id] = (local, upstream)

        local.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close(id)
            default: break
            }
        }
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.pump(from: local, to: upstream, id: id)
                self.pump(from: upstream, to: local, id: id)
            case .failed, .cancelled:
                self.close(id)
            default:
                break
            }
        }
        local.start(queue: queue)
        upstream.start(queue: queue)
    }

    private func pump(from source: NWConnection, to destination: NWConnection, id: UUID) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self, self.connections[id] != nil else { return }
            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { [weak self] sendError in
                    guard let self, self.connections[id] != nil else { return }
                    if sendError == nil, !complete, error == nil {
                        self.pump(from: source, to: destination, id: id)
                    } else {
                        self.close(id)
                    }
                })
            } else if complete || error != nil {
                self.close(id)
            } else {
                self.pump(from: source, to: destination, id: id)
            }
        }
    }
}
