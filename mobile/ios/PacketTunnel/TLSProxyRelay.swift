import Foundation
import Network

final class TLSProxyRelay {
    private let upstreamHost: NWEndpoint.Host
    private let upstreamPort: NWEndpoint.Port
    private let queue = DispatchQueue(label: "ru.arvectum.proxylauncher.ios.tlsrelay")
    private var listener: NWListener?
    private var connections: [NWConnection] = []

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
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
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
            self?.connections.forEach { $0.cancel() }
            self?.connections.removeAll()
        }
    }

    private func handle(_ local: NWConnection) {
        let tls = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let upstream = NWConnection(host: upstreamHost, port: upstreamPort, using: parameters)
        connections.append(contentsOf: [local, upstream])

        local.start(queue: queue)
        upstream.stateUpdateHandler = { [weak self, weak local, weak upstream] state in
            guard let self, let local, let upstream else { return }
            switch state {
            case .ready:
                self.pump(from: local, to: upstream, peer: local)
                self.pump(from: upstream, to: local, peer: upstream)
            case .failed:
                local.cancel()
                upstream.cancel()
            default:
                break
            }
        }
        upstream.start(queue: queue)
    }

    private func pump(from source: NWConnection, to destination: NWConnection, peer: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { [weak self] sendError in
                    guard let self else { return }
                    if sendError == nil, !complete, error == nil {
                        self.pump(from: source, to: destination, peer: peer)
                    } else {
                        source.cancel()
                        destination.cancel()
                    }
                })
            } else if complete || error != nil {
                source.cancel()
                destination.cancel()
            } else {
                self.pump(from: source, to: destination, peer: peer)
            }
        }
    }
}
