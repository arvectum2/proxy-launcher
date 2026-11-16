import Foundation
import Darwin

/// Independent, explicitly scoped runtime-research envelope. Existing
/// validation tickets and ordinary VPN start options cannot authorize it.
struct NativeRuntimeReviewRequest:CustomStringConvertible,CustomReflectable {
    static let mode="native-runtime-review-v1"
    let owner:UUID
    let binding:NativeCredentialHandoff.Binding
    private let ticket:NativeCredentialHandoff.Ticket
    var description:String {"NativeRuntimeReviewRequest(redacted)"}
    var customMirror:Mirror {Mirror(self,children:[:])}
    static func configuration(owner:UUID)->[String:String] {
        [NativeProviderStartRequest.modeKey:mode,NativeProviderStartRequest.ownerKey:owner.uuidString]
    }
    static func ownsConfiguration(_ configuration:[String:Any]?,owner:UUID)->Bool {
        guard let configuration,Set(configuration.keys)==[NativeProviderStartRequest.modeKey,NativeProviderStartRequest.ownerKey] else{return false}
        return configuration[NativeProviderStartRequest.modeKey] as? String==mode && configuration[NativeProviderStartRequest.ownerKey] as? String==owner.uuidString
    }
    static func options(ticket:NativeCredentialHandoff.Ticket,owner:UUID)throws->[String:NSObject] {
        guard ticket.validPurpose,ticket.runtimeOwner==owner,ticket.binding.valid,validScope(ticket) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        return [NativeProviderStartRequest.modeKey:mode as NSString,NativeProviderStartRequest.ownerKey:owner.uuidString as NSString,NativeProviderStartRequest.expectedKey:try TransportNativeCodec.encode(ticket.binding) as NSData,NativeProviderStartRequest.ticketKey:try TransportNativeCodec.encode(ticket) as NSData]
    }
    /// NetworkExtension may attach its own metadata to the transport dictionary.
    /// Only our exact case-sensitive reserved namespace is parsed; an unknown
    /// reserved key is rejected, and no external field grants authority.
    private static func exactNativeOptions(_ options:[String:NSObject])->Bool {
        typealias K=NativeProviderStartRequest
        let names=Set(options.keys.filter{K.hasReservedKey([$0])})
        return options.count<=32 && names==[K.modeKey,K.ownerKey,K.expectedKey,K.ticketKey]
    }
    static func inspect(configuration:[String:Any]?,options:[String:NSObject]?,enabled:Bool)->Self? {
        typealias K=NativeProviderStartRequest
        guard enabled,let configuration,let options,
              Set(configuration.keys)==[K.modeKey,K.ownerKey],configuration[K.modeKey] as? String==mode,
              let text=configuration[K.ownerKey] as? String,let owner=UUID(uuidString:text),text==owner.uuidString,
              exactNativeOptions(options),
              options[K.modeKey] as? String==mode,options[K.ownerKey] as? String==text,
              let raw=options[K.expectedKey] as? Data,let bytes=options[K.ticketKey] as? Data,
              let binding=try? TransportNativeCodec.decode(NativeCredentialHandoff.Binding.self,raw),binding.valid,
              let ticket=try? TransportNativeCodec.decode(NativeCredentialHandoff.Ticket.self,bytes),
              ticket.binding==binding,ticket.validPurpose,ticket.runtimeOwner==owner,
              validScope(ticket) else{return nil}
        return .init(owner:owner,binding:binding,ticket:ticket)
    }
#if APL_NATIVE_RUNTIME_QA_DIAGNOSTICS
    // Numeric diagnostic only, no option contents, keys or bearer material.
    // This never authorizes a request; the original inspector stays strict.
    static func rejectionCode(configuration:[String:Any]?,options:[String:NSObject]?)->Int {
        typealias K=NativeProviderStartRequest
        guard let configuration else{return 11}
        guard Set(configuration.keys)==[K.modeKey,K.ownerKey] else{return 12}
        guard configuration[K.modeKey] as? String==mode else{return 13}
        guard let text=configuration[K.ownerKey] as? String,let owner=UUID(uuidString:text),text==owner.uuidString else{return 14}
        guard let options else{return 15}
        let expected:Set<String>=[K.modeKey,K.ownerKey,K.expectedKey,K.ticketKey]
        let keys=Set(options.keys)
        guard expected.isSubset(of:keys) else{return 16}
        guard exactNativeOptions(options) else{return 100+min(49,keys.subtracting(expected).count)}
        guard options[K.modeKey] as? String==mode,options[K.ownerKey] as? String==text else{return 17}
        guard let raw=options[K.expectedKey] as? Data,let bytes=options[K.ticketKey] as? Data else{return 18}
        guard let binding=try? TransportNativeCodec.decode(NativeCredentialHandoff.Binding.self,raw),binding.valid else{return 19}
        guard let ticket=try? TransportNativeCodec.decode(NativeCredentialHandoff.Ticket.self,bytes) else{return 20}
        guard ticket.binding==binding,ticket.validPurpose,ticket.runtimeOwner==owner else{return 21}
        guard validScope(ticket) else{return 22}
        return 23
    }
#endif
    static func validScope(_ ticket:NativeCredentialHandoff.Ticket)->Bool {
        guard ticket.validPurpose,ticket.runtimeOwner != nil else{return false}
        let v4=ticket.runtimeProbeIPv4.flatMap(canonicalIPv4)
        switch (ticket.binding.reference.kind,ticket.runtimeScope) {
        case (.amneziaWG1,nil):return ticket.runtimeProbeIPv4==nil && ticket.runtimeProbeIPv6==nil
        case (.wireGuard,nil),(.vlessReality,nil):return v4 != nil && ticket.runtimeProbeIPv6==nil
        case (.wireGuard,.wireGuardFull):return ticket.runtimeProbeIPv4==nil && ticket.runtimeProbeIPv6==nil
        case (.vlessReality,.vlessDatagrams):return v4 != nil && ticket.runtimeProbeIPv6.flatMap(canonicalIPv6) != nil
        default:return false
        }
    }
    static func canonicalIPv6(_ value:String)->String? {
        guard value.utf8.count<=45,!value.utf8.contains(0) else{return nil}
        var ip=in6_addr()
        guard value.withCString({inet_pton(AF_INET6,$0,&ip)})==1 else{return nil}
        let b=withUnsafeBytes(of:&ip){Array($0)}
        guard b[0]&0xe0==0x20 || b[0]&0xfe==0xfc else{return nil}
        var buf=[CChar](repeating:0,count:Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6,&ip,&buf,socklen_t(buf.count)) != nil,String(cString:buf)==value else{return nil}
        return value
    }
    static func canonicalIPv4(_ value:String)->String? {
        guard value.utf8.count<=15,!value.utf8.contains(0) else{return nil}
        var ip=in_addr()
        guard value.withCString({inet_pton(AF_INET,$0,&ip)})==1 else{return nil}
        let n=UInt32(bigEndian:ip.s_addr),first=n>>24
        guard first != 0,first != 127,first<224,n>>16 != 0xa9fe else{return nil}
        var buf=[CChar](repeating:0,count:Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET,&ip,&buf,socklen_t(buf.count)) != nil,String(cString:buf)==value else{return nil}
        return value
    }
    func consume(via handoff:NativeCredentialHandoff,admission:NativeRoutingAdmission,exactDNSAvailable:Bool=false)throws->NativeRuntimeReviewPlan {
        guard admission.permitsSelection,Self.validScope(ticket),ticket.runtimeScope==nil || exactDNSAvailable else{throw NativeTunnelRoutePlan.Failure.unsupportedPolicy}
        let record=try handoff.redeem(ticket,expected:binding,runtimeOwner:owner)
        let (config,route)=try record.compile(vlessDatagramReview:ticket.runtimeScope == .vlessDatagrams)
        guard record.reference==binding.reference,config.provider==binding.reference.kind.provider,config.wireProtocol==binding.reference.kind.transport,route.provider==config.provider,try handoff.authorizes(binding) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        switch (route,binding.reference.kind) {
        case (.wireGuard(let plan),.amneziaWG1):
            return .init(route:.awg(plan),configuration:config)
        case (.wireGuard(let plan),.wireGuard):
            if ticket.runtimeScope == .wireGuardFull {return .init(route:.xrayWireGuardFull(plan),configuration:config)}
            guard let target=ticket.runtimeProbeIPv4,target != plan.remoteAddress,target != plan.ipv4Address,!plan.dnsServers.contains(target) else{throw NativeTunnelRoutePlan.Failure.conflictingAddress}
            return .init(route:.xray(.init(validation:route,localIPv4:plan.ipv4Address,targetIPv4:target,mtu:plan.mtu)),configuration:config)
        case (.vlessTCP4(let plan),.vlessReality):
            // Internal interface identity only; never remote or probe route.
            let local="192.0.2.177"
            guard let target=ticket.runtimeProbeIPv4,target != local,target != plan.remoteAddress,plan.remoteAddress != local else{throw NativeTunnelRoutePlan.Failure.conflictingAddress}
            if ticket.runtimeScope == .vlessDatagrams {
                let local6="2001:db8:177::2"
                guard let target6=ticket.runtimeProbeIPv6,target6 != local6 else{throw NativeTunnelRoutePlan.Failure.conflictingAddress}
                return .init(route:.xray(.init(validation:route,localIPv4:local,targetIPv4:target,mtu:1500,localIPv6:local6,targetIPv6:target6)),configuration:config)
            }
            return .init(route:.xray(.init(validation:route,localIPv4:local,targetIPv4:target,mtu:1500)),configuration:config)
        default:throw NativeCredentialReceiver.Failure.providerMismatch
        }
    }
}

/// Runtime scope is explicit: AWG full-tunnel review, Xray exact single
/// IPv4 destination only. No substitution for VLESS/WG default/DNS routes.
struct NativeRuntimeReviewPlan:CustomStringConvertible,CustomReflectable {
    struct XrayProbeRoute:Equatable {
        let validation:NativeValidationRoute
        let localIPv4:String
        let targetIPv4:String
        let mtu:Int
        var localIPv6:String?=nil
        var targetIPv6:String?=nil
    }
    enum Route:Equatable {
        case awg(NativeTunnelRoutePlan)
        case xray(XrayProbeRoute)
        case xrayWireGuardFull(NativeTunnelRoutePlan)
    }
    let route:Route
    let configuration:NativeValidationConfiguration
    var description:String {"NativeRuntimeReviewPlan(redacted)"}
    var customMirror:Mirror {Mirror(self,children:[:])}
}
