// Offline object validation only. Never applies OS network settings.
import Foundation
import NetworkExtension

@main struct NativeIPSplitSettingsValidation {
    static func main() throws {
        let local=Data(repeating:17,count:32).base64EncodedString(),peer=Data(repeating:34,count:32).base64EncodedString()
        var count=0
        for awg in [false,true] {
            let extras=awg ? "Jc=0\nJmin=0\nJmax=0\nS1=15\nS2=18\nH1=123456\nH2=67543\nH3=123123\nH4=32345":""
            for endpoint in ["192.0.2.42:51820","[2001:db8::42]:51820"] {
                let text="""
                [Interface]
                PrivateKey = \(local)
                Address = 10.0.0.2/32, fd00::2/128
                DNS = 192.0.2.53, fd00::53
                MTU = 1280
                \(extras)
                [Peer]
                PublicKey = \(peer)
                AllowedIPs = 0.0.0.0/0, ::/0
                Endpoint = \(endpoint)
                """
                let base=try NativeTunnelRoutePlan.prepare(NativeWireGuardRuntimeConfig.compile(text,expected:awg ? .amneziaWG1:.wireGuard))
                for rules in [["198.51.100.7"],["2001:db8:99::/48"],["198.51.100.128/25","2001:0db8:0099::/48"]] {
                    let plan=try NativeIPSplitRoutePlan.prepare(base:base,explicitRules:rules,existingPolicy:.tunnelOnly,explicitIPOptIn:true)
                    let original=NativeTunnelNetworkSettings.make(base),review=NativeTunnelNetworkSettings.makeExplicitIPReview(plan)
                    guard let a=original.ipv4Settings,let b=review.ipv4Settings,let c=original.ipv6Settings,let d=review.ipv6Settings,
                          let dns=review.dnsSettings,let origDNS=original.dnsSettings else{exit(1)}
                    guard original.tunnelRemoteAddress==review.tunnelRemoteAddress,original.mtu==review.mtu,
                          a.addresses==b.addresses,a.subnetMasks==b.subnetMasks,c.addresses==d.addresses,c.networkPrefixLengths==d.networkPrefixLengths,
                          a.includedRoutes?.map({$0.destinationAddress+"/"+$0.destinationSubnetMask})==b.includedRoutes?.map({$0.destinationAddress+"/"+$0.destinationSubnetMask}),
                          c.includedRoutes?.map({$0.destinationAddress+"/"+$0.destinationNetworkPrefixLength.stringValue})==d.includedRoutes?.map({$0.destinationAddress+"/"+$0.destinationNetworkPrefixLength.stringValue}),
                          a.excludedRoutes?.isEmpty==true,c.excludedRoutes?.isEmpty==true,
                          b.excludedRoutes?.map({$0.destinationAddress+"/"+$0.destinationSubnetMask})==plan.ipv4Exclusions.map({$0.address+"/"+($0.ipv4Mask ?? "INVALID")}),
                          d.excludedRoutes?.map({$0.destinationAddress+"/"+$0.destinationNetworkPrefixLength.stringValue})==plan.ipv6Exclusions.map(\.description),
                          dns.servers==origDNS.servers,dns.matchDomains==origDNS.matchDomains,dns.matchDomainsNoSearch==origDNS.matchDomainsNoSearch,
                          review.proxySettings==nil else{exit(2)}
                    count+=1
                }
            }
        }
        guard count==12 else{exit(3)}
        print("NATIVE_EXPLICIT_IP_SETTINGS_OBJECTS_PASS_12_OF_12")
        #if APL_NATIVE_SYNTHETIC_SPLIT_ROUTE
        let lab=try NativeTunnelNetworkSettings.makeSyntheticSplitRoute()
        guard let a=lab.ipv4Settings,let b=lab.ipv6Settings,lab.dnsSettings==nil,lab.proxySettings==nil,lab.tunnelRemoteAddress=="192.168.1.80",lab.mtu==1280,
              a.addresses==["192.0.2.1"],b.addresses==["2001:db8::1"],
              a.includedRoutes?.map({$0.destinationAddress+"/"+$0.destinationSubnetMask})==["192.0.2.2/255.255.255.254"],
              a.excludedRoutes?.map({$0.destinationAddress+"/"+$0.destinationSubnetMask})==["192.0.2.3/255.255.255.255"],
              b.includedRoutes?.map({$0.destinationAddress+"/"+$0.destinationNetworkPrefixLength.stringValue})==["2001:db8::2/127"],
              b.excludedRoutes?.map({$0.destinationAddress+"/"+$0.destinationNetworkPrefixLength.stringValue})==["2001:db8::3/128"] else{exit(4)}
        print("NATIVE_SYNTHETIC_SPLIT_SETTINGS_OBJECT_PASS")
        #endif
    }
}
