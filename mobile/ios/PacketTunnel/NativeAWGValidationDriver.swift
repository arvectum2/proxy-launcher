#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_AWG_CANDIDATE
#if APL_NATIVE_XRAY_CANDIDATE && !APL_NATIVE_UNIFIED_GO_CANDIDATE
#error("Separate Go runtime candidates must not be linked together")
#endif
import Foundation
#if APL_NATIVE_UNIFIED_GO_CANDIDATE
import APLUnifiedGo
#else
import APLAWGBridge
#endif

/// Dedicated Go UAPI validation. The validation bind cannot open or send
/// sockets. No start, packet pump, manager creation or route activation.
enum NativeAWGValidationDriver {
    enum Failure:Error {case unsupported,invalidConfig}
    static func validate(route:NativeValidationRoute,configuration:Data)throws {
#if APL_NATIVE_AWG_PRODUCT_BRIDGE
        try NativeAWGProductFlow.validateDown(route:route,configuration:configuration)
        return
#else
        guard case .wireGuard(let plan)=route,plan.provider == .standaloneAWG else{throw Failure.unsupported}
        guard !configuration.isEmpty,configuration.count<=4096 else{throw Failure.invalidConfig}
        var copy=configuration
        defer{copy.resetBytes(in:0..<copy.count)}
        let code=copy.withUnsafeMutableBytes{aplAWGBridgeValidateConfig($0.baseAddress,Int32($0.count))}
        guard code==0 else{throw Failure.invalidConfig}
#endif
    }
}
#endif
