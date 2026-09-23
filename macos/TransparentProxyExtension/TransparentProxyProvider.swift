import Foundation
import Network
import NetworkExtension

final class TransparentProxyProvider: NETransparentProxyProvider {
    private let stateQueue = DispatchQueue(
        label: "ru.arvectum.proxylauncher.transparent-provider"
    )
    private var configuration: UpstreamProxyConfiguration?
    private var relays: [ObjectIdentifier: HTTPConnectRelay] = [:]
    private var rejectedUDPFlows: [ObjectIdentifier: NEAppProxyUDPFlow] = [:]

    override func startProxy(
        options: [String: Any]? = nil,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            guard let tunnelProtocol = protocolConfiguration
                    as? NETunnelProviderProtocol else {
                throw ProxyConfigurationError.missingProviderConfiguration
            }
            let configuration = try UpstreamProxyConfiguration(
                providerConfiguration: tunnelProtocol.providerConfiguration
            )
            self.configuration = configuration

            let settings = NETransparentProxyNetworkSettings(
                tunnelRemoteAddress: "127.0.0.1"
            )
            settings.includedNetworkRules = Self.interceptionRules()
            setTunnelNetworkSettings(settings) { [weak self] error in
                if error == nil {
                    self?.configuration = configuration
                }
                completionHandler(error)
            }
        } catch {
            completionHandler(error)
        }
    }

    override func stopProxy(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        stateQueue.async {
            let current = Array(self.relays.values)
            self.relays.removeAll()
            self.rejectedUDPFlows.removeAll()
            self.configuration = nil
            current.forEach { $0.cancel() }
            completionHandler()
        }
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        if let tcpFlow = flow as? NEAppProxyTCPFlow {
            return handleTCPFlow(tcpFlow)
        }
        if let udpFlow = flow as? NEAppProxyUDPFlow {
            return rejectUDPFlow(udpFlow)
        }
        return false
    }
    private func handleTCPFlow(_ flow: NEAppProxyTCPFlow) -> Bool {
        guard let configuration,
              let relay = HTTPConnectRelay(
                  flow: flow,
                  configuration: configuration
              ) else {
            return false
        }

        let key = ObjectIdentifier(flow)
        relay.onFinish = { [weak self] in
            self?.stateQueue.async {
                self?.relays.removeValue(forKey: key)
            }
        }
        stateQueue.sync {
            relays[key] = relay
        }
        relay.start()
        return true
    }

    private func rejectUDPFlow(_ flow: NEAppProxyUDPFlow) -> Bool {
        let key = ObjectIdentifier(flow)
        stateQueue.sync {
            rejectedUDPFlows[key] = flow
        }

        flow.open(withLocalEndpoint: nil) { [weak self, weak flow] error in
            guard let self, let flow else { return }
            self.stateQueue.async {
                defer {
                    self.rejectedUDPFlows.removeValue(forKey: key)
                }
                guard error == nil else { return }
                let refused = NSError(
                    domain: NEAppProxyErrorDomain,
                    code: NEAppProxyFlowError.refused.rawValue
                )
                flow.closeReadWithError(refused)
                flow.closeWriteWithError(refused)
            }
        }
        return true
    }

    private static func interceptionRules() -> [NENetworkRule] {
        [
            networkRule(
                address: "0.0.0.0",
                prefix: 0,
                port: "80",
                protocol: .TCP
            ),
            networkRule(
                address: "::",
                prefix: 0,
                port: "80",
                protocol: .TCP
            ),
            networkRule(
                address: "0.0.0.0",
                prefix: 0,
                port: "443",
                protocol: .TCP
            ),
            networkRule(
                address: "::",
                prefix: 0,
                port: "443",
                protocol: .TCP
            ),
            networkRule(
                address: "0.0.0.0",
                prefix: 0,
                port: "443",
                protocol: .UDP
            ),
            networkRule(
                address: "::",
                prefix: 0,
                port: "443",
                protocol: .UDP
            ),
        ]
    }

    private static func networkRule(
        address: String,
        prefix: Int,
        port: String,
        protocol networkProtocol: NENetworkRule.`Protocol`
    ) -> NENetworkRule {
        NENetworkRule(
            destinationNetwork: NWHostEndpoint(
                hostname: address,
                port: port
            ),
            prefix: prefix,
            protocol: networkProtocol
        )
    }
}
