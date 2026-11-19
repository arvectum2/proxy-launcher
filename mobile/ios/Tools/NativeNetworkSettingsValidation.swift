// Offline object validation. Never applies settings, writes preferences or starts VPN.
import Foundation
import NetworkExtension

@main struct NativeNetworkSettingsValidation {
    static func main() throws {
        let local = Data(repeating:17,count:32).base64EncodedString()
        let remote = Data(repeating:34,count:32).base64EncodedString()
        for awg in [false,true] {
            let legacy = awg ? "Jc=0\nJmin=0\nJmax=0\nS1=15\nS2=18\nH1=123456\nH2=67543\nH3=123123\nH4=32345" : ""
            for endpoint in ["192.0.2.42:51820","[2001:db8::42]:51820"] {
                let config = """
                [Interface]
                PrivateKey = \(local)
                Address = 10.0.0.2/32, fd00::2/128
                DNS = 192.0.2.53, fd00::53
                MTU = 1280
                \(legacy)
                [Peer]
                PublicKey = \(remote)
                AllowedIPs = 0.0.0.0/0, ::/0
                Endpoint = \(endpoint)
                """
                let plan = try NativeTunnelRoutePlan.prepare(NativeWireGuardRuntimeConfig.compile(config,expected:awg ? .amneziaWG1 : .wireGuard))
                let ne = NativeTunnelNetworkSettings.make(plan)
                guard let v4 = ne.ipv4Settings, let v6 = ne.ipv6Settings, let dns = ne.dnsSettings else { exit(1) }
                guard ne.tunnelRemoteAddress == plan.remoteAddress, ne.mtu?.intValue == plan.mtu,
                      v4.addresses == [plan.ipv4Address], v4.subnetMasks == ["255.255.255.255"],
                      v4.includedRoutes?.map({$0.destinationAddress+"/"+$0.destinationSubnetMask}) == ["0.0.0.0/0.0.0.0"],
                      v4.excludedRoutes?.isEmpty == true,
                      v6.addresses == [plan.ipv6Address], v6.networkPrefixLengths == [128],
                      v6.includedRoutes?.map({$0.destinationAddress+"/"+$0.destinationNetworkPrefixLength.stringValue}) == plan.ipv6DefaultRoutes,
                      v6.excludedRoutes?.isEmpty == true,
                      dns.servers == plan.dnsServers, dns.matchDomains == [""], dns.matchDomainsNoSearch else { exit(2) }
            }
        }
        print("NATIVE_NETWORK_SETTINGS_OBJECTS_PASS_4_OF_4")
    }
}
