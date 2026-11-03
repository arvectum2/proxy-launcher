#if DEBUG
import Foundation
import Network
import Security

/// Reproducible 20s hardware QA. Produces three ordinary app TCP flows;
/// nothing is persisted and no paid proxy/user session is contacted.
@MainActor enum Smart3PhysicalTrafficQA {
    private static var connections: [NWConnection] = []

    static func begin() {
        guard ProcessInfo.processInfo.arguments.contains("-aplEphemeralTunnelQA"),
              ProcessInfo.processInfo.arguments.contains("-aplSmart3LocalProxyQA") else { return }
        connections.forEach { $0.cancel() }
        connections.removeAll()
        let queue = DispatchQueue(label: "ru.arvectum.apl.smart3.qa-traffic")
        let labDirect = ProcessInfo.processInfo.arguments.contains("-aplSmart3ScopedDirectLabQA")
        let ipv6OnlyLab = labDirect && ProcessInfo.processInfo.arguments.contains("-aplSmart3IPv6OnlyLabQA")
        let target = ipv6OnlyLab ? "ipv6.google.com" : "www.apple.com"
        let hosts = labDirect ? ["www.cloudflare.com", target, target]
                              : ["probe.qa-example.test", "auth.qa-example.test", "auth.qa-example.test"]
        for host in hosts {
            // In scoped lab, the first two target connections perform a
            // genuine TLS handshake WHILE the upstream proxy is stalled.
            // Their original TCP streams must recover without a page reload.
            let parameters: NWParameters
            if labDirect {
                let options = NWProtocolTLS.Options()
                // Never rely on implicit TLS SNI for the IPv6-only Google
                // test; explicit SNI also matches the production TLS probe.
                sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, host)
                parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
            } else {
                parameters = .tcp
            }
            let connection = NWConnection(host: NWEndpoint.Host(host), port: .https,
                                          using: parameters)
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    if labDirect && host == target {
                        TelemetryStore().append(TunnelEvent(type: "lab sameflow tls ready",
                            detail: "Original stalled TLS client became ready without reconnect"))
                    }
                    connection.send(content: Data("GET / HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n".utf8),
                                    completion: .contentProcessed { _ in })
                    if labDirect && host == target {
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) {
                            data, _, _, _ in
                            if let data, !data.isEmpty {
                                TelemetryStore().append(TunnelEvent(type: "lab sameflow tls data",
                                    detail: "Original stalled TLS flow received HTTP response bytes"))
                            }
                        }
                    }
                } else if case .failed = state {
                    if labDirect && host == target {
                        TelemetryStore().append(TunnelEvent(type: "lab sameflow tls failed",
                            detail: "Original stalled TLS transport failed before application response"))
                    }
                }
            }
            connection.start(queue: queue)
            connections.append(connection)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds:
                labDirect ? 18_000_000_000 : 16_000_000_000)
            if labDirect {
                // A fresh fourth connection after the two proxy timeouts and
                // independent TLS probes tests actual per-flow routing.
                let host = target
                let options = NWProtocolTLS.Options()
                sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, host)
                let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
                let direct = NWConnection(host: NWEndpoint.Host(host), port: .https,
                                          using: parameters)
                direct.stateUpdateHandler = { state in
                    if case .ready = state {
                        TelemetryStore().append(TunnelEvent(type: "lab scoped tls ready",
                            detail: "Fourth TLS session succeeded with mock proxy denying target"))
                        print("APL_SCOPED_QA_TLS_READY")
                        direct.send(content: Data("GET / HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n".utf8),
                                    completion: .contentProcessed { _ in })
                        direct.receive(minimumIncompleteLength: 1, maximumLength: 256) {
                            data, _, _, _ in
                            if let data, !data.isEmpty {
                                TelemetryStore().append(TunnelEvent(type: "lab scoped tls data",
                                    detail: "Direct test TLS replied with bytes"))
                            }
                            print("APL_SCOPED_QA_RESPONSE_BYTES_\(data?.count ?? 0)")
                        }
                    } else if case .failed = state {
                        TelemetryStore().append(TunnelEvent(type: "lab scoped tls failed",
                            detail: "Fourth TLS session was unable to connect"))
                    }
                }
                TelemetryStore().append(TunnelEvent(type: "lab scoped tls attempt",
                    detail: "Fourth independent connection after direct policy armed"))
                direct.start(queue: queue)
                connections.append(direct)
                if ProcessInfo.processInfo.arguments.contains("-aplSmart3OpaqueTrafficLabQA") {
                    // All three paths are opaque to an exact HTTP/TLS hostname
                    // rule: a raw IP, an HTTPS DoH endpoint, and genuine
                    // QUIC/UDP port 443. The mock NEVER forwards these.
                    for (host, marker) in [
                        ("23.12.156.37", "lab raw ip proxy tcp ready"),
                        ("dns.google", "lab doh endpoint proxy tcp ready")
                    ] {
                        let opaque = NWConnection(host: NWEndpoint.Host(host),
                                                  port: .https, using: .tcp)
                        opaque.stateUpdateHandler = { state in
                            if case .ready = state {
                                TelemetryStore().append(TunnelEvent(type: marker,
                                    detail: "Non-approved destination connected via mock upstream"))
                            }
                        }
                        opaque.start(queue: queue)
                        connections.append(opaque)
                    }
                    // Send a genuine Network.framework QUIC Initial over
                    // UDP/443. The upstream HTTP mock has NO UDP relay, so
                    // connection success is not expected. What matters is that
                    // tun2proxy processes it exclusively as UDP, not DIRECT.
                    let quicParameters = NWParameters(quic: NWProtocolQUIC.Options(alpn: ["h3"]))
                    let quic = NWConnection(host: NWEndpoint.Host(target),
                                            port: .https, using: quicParameters)
                    quic.stateUpdateHandler = { state in
                        if case .failed = state {
                            TelemetryStore().append(TunnelEvent(type: "lab opaque quic refused",
                                detail: "Mock HTTP proxy cannot forward QUIC; no direct fallback"))
                        }
                    }
                    quic.start(queue: queue)
                    TelemetryStore().append(TunnelEvent(type: "lab opaque quic started",
                        detail: "Actual Network.framework QUIC h3 handshake attempted"))
                    connections.append(quic)
                }
                if ipv6OnlyLab {
                    // Same IPv6 physical endpoint via canonical CNAME, but
                    // separate VirtualDNS hostname: never inherit DIRECT.
                    let neighbor = NWConnection(host: "ipv6.l.google.com",
                                                port: .https, using: .tcp)
                    neighbor.stateUpdateHandler = { state in
                        if case .ready = state {
                            TelemetryStore().append(TunnelEvent(
                                type: "lab ipv6 neighbor tcp ready",
                                detail: "Different IPv6 virtual DNS name used mock proxy"))
                        }
                    }
                    neighbor.start(queue: queue)
                    connections.append(neighbor)
                }
                if ProcessInfo.processInfo.arguments.contains("-aplSmart3SharedIPLabQA") {
                    // Different exact VirtualDNS identity, same observed CDN
                    // IPv4 as approved apple.com. Must remain upstream proxy.
                    let peer = NWConnection(host: "www.apple.com.cn",
                                            port: .https, using: .tcp)
                    peer.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            TelemetryStore().append(TunnelEvent(
                                type: "lab neighbor tcp ready",
                                detail: "Distinct CDN hostname connected over proxy"))
                        case .failed:
                            TelemetryStore().append(TunnelEvent(
                                type: "lab neighbor tcp failed",
                                detail: "Distinct CDN hostname TCP failed"))
                        default: break
                        }
                    }
                    peer.start(queue: queue)
                    connections.append(peer)
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }
}
#endif
