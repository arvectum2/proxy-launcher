// Synthetic-only standard WG config builder. No storage or production target.
import Foundation

enum XrayWireGuardLabConfig {
    enum Failure: Error { case unsupported }
    static func prepare(_ text: String, port: Int, dual: Bool = false, physical: Bool = false) throws -> String {
        let preview = try WGQuickConfigurationPreview.parse(text)
        let addresses = dual ? ["10.77.0.2/32", "2001:db8:77::2/128"] : ["10.77.0.2/32"]
        let targets = dual ? ["198.51.100.77/32", "2001:db8:77::77/128"] : ["198.51.100.77/32"]
        let endpoint = physical ? "192.168.1.80:39881" : "127.0.0.1:39881"
        guard preview.format == .wireGuard, Set(preview.addresses) == Set(addresses), preview.addresses.count == addresses.count,
              preview.dnsServers.isEmpty, preview.peers.count == 1,
              preview.peers[0].endpoint == endpoint,
              Set(preview.peers[0].allowedIPs) == Set(targets), preview.peers[0].allowedIPs.count == targets.count,
              port == 39879 else { throw Failure.unsupported }
        var values = [String:String]()
        var section = ""
        for raw in text.components(separatedBy:.newlines) {
            let line=String(raw.prefix{$0 != "#"}).trimmingCharacters(in:.whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("[") { section=line.lowercased(); continue }
            guard let eq=line.firstIndex(of:"=") else { throw Failure.unsupported }
            let key=section+line[..<eq].trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
            values[key]=line[line.index(after:eq)...].trimmingCharacters(in:.whitespacesAndNewlines)
        }
        func key(_ label:String) throws -> String {
            guard let raw=values[label], let data=Data(base64Encoded:raw), data.count==32,
                  data.contains(where:{$0 != 0}), data.base64EncodedString()==raw else { throw Failure.unsupported }
            return raw
        }
        guard Set(values.keys).isSubset(of:["[interface]privatekey","[interface]address",
                  "[peer]publickey","[peer]presharedkey","[peer]endpoint","[peer]allowedips"]) else {
            throw Failure.unsupported
        }
        var peer:[String:Any] = ["publicKey":try key("[peer]publickey"),
            "endpoint":endpoint,"allowedIPs":targets]
        if values["[peer]presharedkey"] != nil { peer["preSharedKey"]=try key("[peer]presharedkey") }
        let cfg:[String:Any] = [
            "log":["loglevel":"none"],
            "inbounds":[["tag":"lab-socks","listen":"127.0.0.1","port":port,
                         "protocol":"socks","settings":["auth":"noauth","udp":dual,"ip":"127.0.0.1"]]],
            "outbounds":[["tag":"lab-wg","protocol":"wireguard",
                          "settings":["secretKey":try key("[interface]privatekey"),
                                      "address":addresses,"noKernelTun":true,
                                      "mtu":1280,"peers":[peer]]]],
            "routing":["domainStrategy":"AsIs","rules":[["type":"field","inboundTag":["lab-socks"],"outboundTag":"lab-wg"]]]
        ]
        return String(decoding:try JSONSerialization.data(withJSONObject:cfg),as:UTF8.self)
    }
}
