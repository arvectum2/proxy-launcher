#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_SYNTHETIC_RUNTIME && APL_NATIVE_XRAY_CANDIDATE
import Foundation

enum NativeSyntheticRuntimeFixture {
    enum Failure:Error {case unsupported}
    static func compile(_ request:NativeSyntheticRuntimeRequest)throws -> (NativeValidationRoute,Data) {
        guard let source=String(data:request.fixture,encoding:.utf8) else{throw Failure.unsupported}
        switch request.binding.reference.kind {
        case .wireGuard:
            let cfg=try XrayWireGuardLabConfig.prepare(source,port:39879,dual:true,physical:true)
            // Only the exact previously tested remote/host routes; this plan
            // is metadata for the scoped candidate, never general routing.
            let route=NativeTunnelRoutePlan(provider:.rustXray,ipv4Address:"10.77.0.2",ipv6Address:"2001:db8:77::2",remoteAddress:"192.168.1.80",remotePort:39881,dnsServers:[],mtu:1280)
            return (.wireGuard(route),Data(cfg.utf8))
        case .vlessReality:
            let candidate=try VLESSRealityShareLink.parse(source)
            guard candidate.serverHost=="192.168.1.80",candidate.serverPort==39882,candidate.serverName=="example.com" else{throw Failure.unsupported}
            return (.vlessTCP4(try NativeVLESSValidationPlan.prepare(candidate)),try XrayVLESSRuntimeConfig.compileValidatedCandidate(candidate,socksPort:39879))
        default:throw Failure.unsupported
        }
    }
}
#endif
