import Foundation
import Darwin

/// Explicit user-authored literal network only. No DNS resolution, hostname
/// conversion or implicit expansion of a host to a larger network.
struct NativeLiteralIPPrefix: Hashable, CustomStringConvertible {
    enum Failure:Error,Equatable {case malformed,nonCanonicalNetwork,unsupportedRange}
    let address:String
    let length:Int
    private let bytes:[UInt8]
    var isIPv6:Bool {bytes.count==16}
    var description:String {"\(address)/\(length)"}
    var ipv4Mask:String? {
        guard !isIPv6 else{return nil}
        return (0..<4).map {i in String(Self.maskOctet(length-i*8))}.joined(separator:".")
    }
    private static func maskOctet(_ bits:Int)->UInt8 {
        if bits<=0{return 0};if bits>=8{return 255};return UInt8(256-(1<<(8-bits)))
    }
    init(_ raw:String)throws {
        guard !raw.isEmpty,raw.utf8.count<=64,raw.utf8.allSatisfy({(48...57).contains($0)||(65...70).contains($0)||(97...102).contains($0)||[46,58,47].contains($0)}) else{throw Failure.malformed}
        let parts=raw.split(separator:"/",omittingEmptySubsequences:false)
        guard (1...2).contains(parts.count),!parts[0].isEmpty else{throw Failure.malformed}
        let host=String(parts[0]);var v4=in_addr(),v6=in6_addr();var output=[CChar](repeating:0,count:Int(INET6_ADDRSTRLEN));let b:[UInt8]
        if host.withCString({inet_pton(AF_INET,$0,&v4)})==1 {
            b=withUnsafeBytes(of:&v4){Array($0)}
            guard inet_ntop(AF_INET,&v4,&output,socklen_t(output.count)) != nil else{throw Failure.malformed}
        } else if host.withCString({inet_pton(AF_INET6,$0,&v6)})==1 {
            b=withUnsafeBytes(of:&v6){Array($0)}
            guard inet_ntop(AF_INET6,&v6,&output,socklen_t(output.count)) != nil else{throw Failure.malformed}
        } else {throw Failure.malformed}
        let max=b.count*8;let n:Int
        if parts.count==2 {
            guard let x=Int(parts[1]),String(x)==parts[1],(1...max).contains(x) else{throw Failure.malformed};n=x
        } else {n=max}
        guard b.enumerated().allSatisfy({i,x in x & Self.maskOctet(n-i*8)==x}) else{throw Failure.nonCanonicalNetwork}
        // Prohibit the entire range if it overlaps non-unicast/special
        // blocks, not merely if its first address happens to be special.
        if b.count==4 {
            for (block,bits):([UInt8],Int) in [([0,0,0,0],8),([127,0,0,0],8),([169,254,0,0],16),([224,0,0,0],3)] {
                if Self.samePrefix(b,block,min(n,bits)){throw Failure.unsupportedRange}
            }
        } else {
            guard (n>=3 && b[0]&0xe0==0x20) || (n>=7 && b[0]&0xfe==0xfc) else{throw Failure.unsupportedRange}
        }
        bytes=b;length=n;address=String(cString:output)
    }
    private static func samePrefix(_ a:[UInt8],_ b:[UInt8],_ bits:Int)->Bool {
        a.count==b.count && a.indices.allSatisfy{(a[$0]&maskOctet(bits-$0*8))==(b[$0]&maskOctet(bits-$0*8))}
    }
    func overlaps(_ other:Self)->Bool {Self.samePrefix(bytes,other.bytes,min(length,other.length))}
    static func ordered(_ a:Self,_ b:Self)->Bool {
        if a.bytes.count != b.bytes.count{return a.bytes.count<b.bytes.count}
        if a.bytes != b.bytes{return a.bytes.lexicographicallyPrecedes(b.bytes)}
        return a.length<b.length
    }
}

/// Review-only capability for WG/AWG full-tunnel settings with explicit IP
/// exceptions. Does not change the normal native admission or backend policy.
/// IP exceptions apply to *all* traffic to that network, not a particular host.
struct NativeIPSplitRoutePlan:Equatable {
    enum Failure:Error,Equatable {case explicitConsentRequired,existingPolicyConflict,invalidBase,invalidCount,overlap,protectedAddress}
    let base:NativeTunnelRoutePlan
    let exclusions:[NativeLiteralIPPrefix]
    var ipv4Exclusions:[NativeLiteralIPPrefix] {exclusions.filter{!$0.isIPv6}}
    var ipv6Exclusions:[NativeLiteralIPPrefix] {exclusions.filter{$0.isIPv6}}
    private init(base:NativeTunnelRoutePlan,exclusions:[NativeLiteralIPPrefix]) {self.base=base;self.exclusions=exclusions}
    static func prepare(base:NativeTunnelRoutePlan,explicitRules:[String],existingPolicy:NativeRoutingAdmission,explicitIPOptIn:Bool)throws->Self {
        guard explicitIPOptIn else{throw Failure.explicitConsentRequired}
        guard existingPolicy == .tunnelOnly else{throw Failure.existingPolicyConflict}
        guard (1...64).contains(explicitRules.count) else{throw Failure.invalidCount}
        // Revalidate even if a synthetic caller directly constructed the base.
        guard (1280...1500).contains(base.mtu),base.remotePort>0,(1...16).contains(base.dnsServers.count) else{throw Failure.invalidBase}
        let protect=try ([base.ipv4Address,base.ipv6Address,base.remoteAddress]+base.dnsServers).map {raw -> NativeLiteralIPPrefix in
            guard !raw.contains("/") else{throw Failure.invalidBase}
            let p=try NativeLiteralIPPrefix(raw);guard raw==p.address else{throw Failure.invalidBase};return p
        }
        guard !protect[0].isIPv6,protect[1].isIPv6,Set(protect).count==protect.count else{throw Failure.invalidBase}
        let rules=try explicitRules.map(NativeLiteralIPPrefix.init).sorted(by:NativeLiteralIPPrefix.ordered)
        for (index,rule) in rules.enumerated() {
            guard !protect.contains(where:{rule.overlaps($0)}) else{throw Failure.protectedAddress}
            guard !rules[..<index].contains(where:{rule.overlaps($0)}) else{throw Failure.overlap}
        }
        return .init(base:base,exclusions:rules)
    }
}

/// Fixed documentation-address QA plan, not a full-tunnel production plan.
/// The adjacent excluded address must have an independently provisioned
/// isolated external witness before any physical test; no such route is created here.
struct NativeSyntheticSplitRoutePlan:Equatable {
    enum ProbeCase:String,Codable {case included,excluded}
    let included:[NativeLiteralIPPrefix]
    let excluded:[NativeLiteralIPPrefix]
    private init(included:[NativeLiteralIPPrefix],excluded:[NativeLiteralIPPrefix]){self.included=included;self.excluded=excluded}
    static func prepare()throws->Self {
        .init(included:try ["192.0.2.2/31","2001:db8::2/127"].map(NativeLiteralIPPrefix.init),excluded:try ["192.0.2.3/32","2001:db8::3/128"].map(NativeLiteralIPPrefix.init))
    }
    static func target(_ probe:ProbeCase,ipv6:Bool)->String {
        switch (probe,ipv6){case (.included,false):return "192.0.2.2";case (.excluded,false):return "192.0.2.3";case (.included,true):return "2001:db8::2";case (.excluded,true):return "2001:db8::3"}
    }
}
