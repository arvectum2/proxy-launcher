import Foundation
@preconcurrency import Network
@preconcurrency import NetworkExtension

final class HTTPConnectRelay {
    enum RelayError: Error {
        case unsupportedEndpoint
        case upstreamRejected(Int)
        case malformedUpstreamResponse
        case responseHeaderTooLarge
    }

    private let flow: NEAppProxyTCPFlow
    private let configuration: UpstreamProxyConfiguration
    private let targetHost: String
    private let targetPort: UInt16
    private let queue: DispatchQueue
    private let connection: NWConnection
    private var responseBuffer = Data()
    private var finished = false
    private var flowOpened = false

    var onFinish: (() -> Void)?

    init?(
        flow: NEAppProxyTCPFlow,
        configuration: UpstreamProxyConfiguration
    ) {
        guard let endpoint = flow.remoteEndpoint as? NWHostEndpoint,
              let port = UInt16(endpoint.port) else {
            return nil
        }
        let hostname = flow.remoteHostname
        let targetHost = (hostname?.isEmpty == false)
            ? hostname!
            : endpoint.hostname
        guard !targetHost.isEmpty else { return nil }

        self.flow = flow
        self.configuration = configuration
        self.targetHost = targetHost
        self.targetPort = port
        self.queue = DispatchQueue(
            label: "ru.arvectum.proxylauncher.transparent-relay.\(UUID().uuidString)"
        )
        self.connection = NWConnection(
            host: configuration.nwHost,
            port: configuration.nwPort,
            using: .tcp
        )
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendConnectRequest()
            case .failed:
                self.finish(flowError: .hostUnreachable)
            case .cancelled:
                self.finish(flowError: nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
    func cancel() {
        queue.async { [weak self] in
            self?.finish(flowError: .aborted)
        }
    }

    private func sendConnectRequest() {
        var request = "CONNECT \(authority) HTTP/1.1\r\n"
        request += "Host: \(authority)\r\n"
        request += "Proxy-Connection: Keep-Alive\r\n"
        if let auth = configuration.proxyAuthorizationHeader {
            request += "Proxy-Authorization: \(auth)\r\n"
        }
        request += "\r\n"

        connection.send(
            content: Data(request.utf8),
            completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                self.queue.async {
                    if error != nil {
                        self.finish(flowError: .hostUnreachable)
                        return
                    }
                    self.readConnectResponse()
                }
            }
        )
    }

    private func readConnectResponse() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16_384
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                if error != nil {
                    self.finish(flowError: .hostUnreachable)
                    return
                }
                if let data, !data.isEmpty {
                    self.responseBuffer.append(data)
                }
                if self.responseBuffer.count > 65_536 {
                    self.finish(flowError: .internal)
                    return
                }
                if let end = self.responseBuffer.range(
                    of: Data("\r\n\r\n".utf8)
                ) {
                    self.finishConnectHandshake(headerEnd: end.upperBound)
                    return
                }
                if isComplete {
                    self.finish(flowError: .hostUnreachable)
                    return
                }
                self.readConnectResponse()
            }
        }
    }

    private func finishConnectHandshake(headerEnd: Data.Index) {
        let header = responseBuffer[..<headerEnd]
        guard let text = String(data: header, encoding: .isoLatin1),
              let firstLine = text.components(separatedBy: "\r\n").first else {
            finish(flowError: .internal)
            return
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, let status = Int(parts[1]) else {
            finish(flowError: .internal)
            return
        }
        guard status == 200 else {
            finish(flowError: .refused)
            return
        }

        let trailing = Data(responseBuffer[headerEnd...])
        responseBuffer.removeAll(keepingCapacity: false)

        flow.open(withLocalEndpoint: nil) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                if error != nil {
                    self.finish(flowError: .internal)
                    return
                }
                self.flowOpened = true
                if trailing.isEmpty {
                    self.startPumps()
                } else {
                    self.flow.write(trailing) { [weak self] error in
                        guard let self else { return }
                        self.queue.async {
                            if error != nil {
                                self.finish(flowError: .internal)
                            } else {
                                self.startPumps()
                            }
                        }
                    }
                }
            }
        }
    }

    private func startPumps() {
        pumpClientToUpstream()
        pumpUpstreamToClient()
    }
    private func pumpClientToUpstream() {
        flow.readData { [weak self] data, error in
            guard let self else { return }
            self.queue.async {
                if error != nil {
                    self.finish(flowError: .aborted)
                    return
                }
                guard let data, !data.isEmpty else {
                    self.finish(flowError: nil)
                    return
                }
                self.connection.send(
                    content: data,
                    completion: .contentProcessed { [weak self] error in
                        guard let self else { return }
                        self.queue.async {
                            if error != nil {
                                self.finish(flowError: .hostUnreachable)
                            } else {
                                self.pumpClientToUpstream()
                            }
                        }
                    }
                )
            }
        }
    }

    private func pumpUpstreamToClient() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65_536
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                if error != nil {
                    self.finish(flowError: .hostUnreachable)
                    return
                }
                if let data, !data.isEmpty {
                    self.flow.write(data) { [weak self] writeError in
                        guard let self else { return }
                        self.queue.async {
                            if writeError != nil {
                                self.finish(flowError: .aborted)
                            } else if isComplete {
                                self.finish(flowError: nil)
                            } else {
                                self.pumpUpstreamToClient()
                            }
                        }
                    }
                    return
                }
                if isComplete {
                    self.finish(flowError: nil)
                } else {
                    self.pumpUpstreamToClient()
                }
            }
        }
    }

    private func finish(flowError code: NEAppProxyFlowError.Code?) {
        guard !finished else { return }
        finished = true

        connection.stateUpdateHandler = nil
        connection.cancel()

        if flowOpened {
            let error = code.map {
                NSError(domain: NEAppProxyErrorDomain, code: $0.rawValue)
            }
            flow.closeReadWithError(error)
            flow.closeWriteWithError(error)
        }
        let callback = onFinish
        onFinish = nil
        callback?()
    }

    private var authority: String {
        let host = targetHost.contains(":")
            ? "[\(targetHost)]"
            : targetHost
        return "\(host):\(targetPort)"
    }
}
