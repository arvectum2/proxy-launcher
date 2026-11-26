import Foundation
import Darwin

/// Compilation-only candidate. It cannot prepare a production backend plan,
/// start an engine, install routes or write user credentials. Initially a
/// deliberately narrow single-peer, literal-endpoint, dual-stack full-tunnel
/// profile; DNS/underlay and route application still need separate acceptance.
struct NativeWireGuardRuntimeConfig: CustomStringConvertible, CustomReflectable {
    enum Failure: Error, Equatable { case protocolMismatch, unsupportedProfile, invalidKey, invalidPort }
    let wireProtocol: TransportProtocol
    let provider: TransportProvider
    let addresses: [String]
    let dnsServers: [String]
    let remoteEndpoint: String
    let mtu: Int
    private let bytes: Data
    var description: String { "NativeWireGuardRuntimeConfig(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:]) }
    // Explicit ephemeral delivery only; not serializable or a storage format.
    func withEngineConfiguration<T>(_ body: (Data) throws -> T) rethrows -> T { try body(bytes) }

    static func compile(_ config: String, expected: TransportProtocol, socksPort: Int = 39879) throws -> Self {
        let parsed = try WGQuickConfigurationPreview.validated(config)
        let preview = parsed.preview
        let provider: TransportProvider
        switch (expected, preview.format) {
        case (.wireGuard,.wireGuard): provider = .rustXray
        case (.amneziaWG1,.amneziaWG1): provider = .standaloneAWG
        default: throw Failure.protocolMismatch
        }
        guard preview.peers.count == 1, let peer = preview.peers.first,
              preview.addresses.count == 2,
              preview.addresses.filter({ $0.hasSuffix("/32") && !$0.contains(":") }).count == 1,
              preview.addresses.filter({ $0.hasSuffix("/128") && $0.contains(":") }).count == 1,
              Set(peer.allowedIPs) == ["0.0.0.0/0", "::/0"], peer.allowedIPs.count == 2,
              !preview.dnsServers.isEmpty, Set(preview.dnsServers).count == preview.dnsServers.count,
              literalEndpoint(peer.endpoint), parsed.properties["listenport"] == nil else { throw Failure.unsupportedProfile }
        let mtu = Int(parsed.properties["mtu"] ?? "1280") ?? 0
        guard (1280...1500).contains(mtu) else { throw Failure.unsupportedProfile }
        func key(_ raw: String?) throws -> Data {
            guard let raw, let data = Data(base64Encoded: raw), data.count == 32,
                  data.contains(where: {$0 != 0}), data.base64EncodedString() == raw else { throw Failure.invalidKey }
            return data
        }
        let local = try key(parsed.properties["privatekey"])
        let remote = try key(parsed.peerProperties[0]["publickey"])
        let psk = try parsed.peerProperties[0]["presharedkey"].map { try key($0) }
        let keepalive = Int(parsed.peerProperties[0]["persistentkeepalive"] ?? "0") ?? -1
        guard (0...65535).contains(keepalive) else { throw Failure.unsupportedProfile }
        let bytes: Data
        if provider == .rustXray {
            guard (1024...65535).contains(socksPort) else { throw Failure.invalidPort }
            var p: [String:Any] = ["publicKey":remote.base64EncodedString(), "endpoint":peer.endpoint,
                "allowedIPs":peer.allowedIPs, "keepAlive":keepalive]
            if let psk { p["preSharedKey"] = psk.base64EncodedString() }
            let root: [String:Any] = ["log":["loglevel":"none"],
                "inbounds":[["tag":"apl-local","listen":"127.0.0.1","port":socksPort,"protocol":"socks",
                             "settings":["auth":"noauth","udp":true,"ip":"127.0.0.1"]]],
                "outbounds":[["tag":"apl-wg","protocol":"wireguard","settings":["secretKey":local.base64EncodedString(),
                            "address":preview.addresses,"noKernelTun":true,"mtu":mtu,"peers":[p]]]],
                "routing":["domainStrategy":"AsIs","rules":[["type":"field","inboundTag":["apl-local"],"outboundTag":"apl-wg"]]]]
            bytes = try JSONSerialization.data(withJSONObject:root,options:[.sortedKeys])
        } else {
            // UAPI for pinned AWG engine; fixed numeric legacy parameters only.
            func hex(_ data: Data) -> String { data.map { String(format:"%02x",$0) }.joined() }
            var lines = ["private_key="+hex(local),"listen_port=0","replace_peers=true"]
            for k in ["jc","jmin","jmax","s1","s2","h1","h2","h3","h4"] {
                guard let n = parsed.properties[k].flatMap(UInt32.init) else { throw Failure.unsupportedProfile }
                lines.append(k+"="+String(n))
            }
            lines += ["public_key="+hex(remote),"endpoint="+peer.endpoint,"persistent_keepalive_interval="+String(keepalive),"replace_allowed_ips=true"]
            if let psk { lines.append("preshared_key="+hex(psk)) }
            lines += peer.allowedIPs.map { "allowed_ip="+$0 }
            bytes = Data((lines.joined(separator:"\n")+"\n").utf8)
        }
        return .init(wireProtocol:expected,provider:provider,addresses:preview.addresses,dnsServers:preview.dnsServers,remoteEndpoint:peer.endpoint,mtu:mtu,bytes:bytes)
    }
    private static func literalEndpoint(_ endpoint: String) -> Bool {
        var addr4 = in_addr(), addr6 = in6_addr()
        if endpoint.hasPrefix("["), let end = endpoint.firstIndex(of:"]") {
            let host = String(endpoint[endpoint.index(after:endpoint.startIndex)..<end])
            return host.withCString { inet_pton(AF_INET6,$0,&addr6) == 1 }
        }
        guard let colon = endpoint.firstIndex(of:":") else { return false }
        return String(endpoint[..<colon]).withCString { inet_pton(AF_INET,$0,&addr4) == 1 }
    }
}
