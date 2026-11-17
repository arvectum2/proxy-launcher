#if (DEBUG || APL_NATIVE_RELEASE_LINK_PREPARATION || APL_NATIVE_PRODUCT_RUNTIME) && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_XRAY_CANDIDATE
import Foundation
import Darwin
import CoreFoundation
#if APL_NATIVE_UNIFIED_GO_CANDIDATE
import APLUnifiedGo
#else
import LibXray
#endif
import tun2proxy

/// Concrete v3 C ABI, compiled only against the exact unsigned source
/// candidate. No returned error string or request/configuration is logged.
/// Runtime methods are not reachable from PacketTunnel startup yet.
final class NativeXrayRuntimeDriver {
    enum Failure:Error {case invalidReply,wrongVersion,invalidState,invalidConfiguration,unsupportedProvider}
    private enum Method:String {case version="xrayVersion",state="getXrayState",test="testXray",run="runXray",stop="stopXray"}
    private static let maxConfigBytes=65_536
    static let shared=NativeXrayRuntimeDriver()
    private init() {}
    private let lock=NSLock()
    private var runtimeOwner:NativeCredentialHandoff.Binding?
    private var poisoned=false

    private func call(_ method:Method,configuration:Data?=nil)throws -> [String:Any] {
        var req:[String:Any] = ["apiVersion":3,"method":method.rawValue]
        if let configuration {
            guard !configuration.isEmpty,configuration.count<=Self.maxConfigBytes,
                let text=String(data:configuration,encoding:.utf8) else{throw Failure.invalidConfiguration}
            req["payload"]=["xrayJson":text]
        }
        let bytes=try JSONSerialization.data(withJSONObject:req)
        guard let input=strdup(String(decoding:bytes,as:UTF8.self)) else{throw Failure.invalidReply}
        defer{free(input)}
        guard let reply=CGoInvoke(input) else{throw Failure.invalidReply}
        defer{CGoFree(reply)}
        let length=strnlen(reply,XrayVLESSRuntimeConfig.maxResponseBytes+1)
        guard length>0,length<=XrayVLESSRuntimeConfig.maxResponseBytes,
              let root=try? JSONSerialization.jsonObject(with:Data(bytes:reply,count:length)) as? [String:Any],
              let success=root["success"] as? NSNumber,CFGetTypeID(success)==CFBooleanGetTypeID(),success.boolValue else{throw Failure.invalidReply}
        return root
    }
    private func running()throws->Bool {
        guard let value=(try call(.state)["data"] as? [String:Any])?["running"] as? NSNumber,
              CFGetTypeID(value)==CFBooleanGetTypeID() else{throw Failure.invalidReply}
        return value.boolValue
    }
    private func preflightLocked(route:NativeValidationRoute,configuration:Data)throws {
        guard route.provider == .rustXray else{throw Failure.unsupportedProvider}
        guard !poisoned,runtimeOwner==nil else{throw Failure.invalidState}
        guard (try call(.version)["data"] as? [String:Any])?["version"] as? String=="26.11.9" else{throw Failure.wrongVersion}
        guard try !running() else{throw Failure.invalidState}
        do {
            _=try call(.test,configuration:configuration)
            guard try !running() else{throw Failure.invalidState}
        } catch {
            if (try? running()) != false {poisoned=true}
            throw error
        }
    }
    /// Only this non-running preflight is currently wired to the real provider.
    func validate(route:NativeValidationRoute,configuration:Data)throws {
        lock.lock();defer{lock.unlock()}
        try preflightLocked(route:route,configuration:configuration)
    }
    /// Concrete engine ownership API for the upcoming separately authorized
    /// data-plane integration. No caller in this stage; no OS routing here.
    func startXray(owner:NativeCredentialHandoff.Binding,route:NativeValidationRoute,configuration:Data)throws {
        lock.lock();defer{lock.unlock()}
        guard owner.valid,owner.reference.kind.provider == .rustXray else{throw Failure.unsupportedProvider}
        switch (owner.reference.kind,route) {
        case (.wireGuard,.wireGuard),(.vlessReality,.vlessTCP4):break
        default:throw Failure.unsupportedProvider
        }
        try preflightLocked(route:route,configuration:configuration)
        runtimeOwner=owner // even an ambiguous C failure requires exact cleanup
        do{_=try call(.run,configuration:configuration);guard try running() else{throw Failure.invalidState}}
        catch{poisoned=true;throw error}
    }
    func stopOwnedXray(owner:NativeCredentialHandoff.Binding)throws {
        lock.lock();defer{lock.unlock()}
        guard runtimeOwner==owner else{throw Failure.invalidState}
        do{_=try call(.stop);guard try !running() else{throw Failure.invalidState};runtimeOwner=nil}
        catch{poisoned=true;throw error}
    }
    /// Actual Rust stop/drain primitive, callable only by a future owner of
    /// the serial runner queue. Never infer drain from a stop return code.
    static func drainOwnedRustRunner(queue:DispatchQueue)async throws {
        try await TunnelEngineHandoff.stopAndDrain(engineQueue:queue,timeout:5){_=tun2proxy_stop()}
    }
}
#endif
