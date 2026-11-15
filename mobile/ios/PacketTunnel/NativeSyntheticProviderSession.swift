#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_SYNTHETIC_RUNTIME
import Foundation
import NetworkExtension

#if !APL_NATIVE_XRAY_CANDIDATE && !APL_NATIVE_AWG_CANDIDATE
#error("Synthetic runtime requires a candidate engine")
#endif

#if APL_NATIVE_UNIFIED_GO_CANDIDATE && (!APL_NATIVE_XRAY_CANDIDATE || !APL_NATIVE_AWG_CANDIDATE)
#error("Unified candidate requires both driver gates")
#endif

@MainActor protocol NativeSyntheticProviderSession:AnyObject {
    func start(provider:NEPacketTunnelProvider,request:NativeSyntheticRuntimeRequest) async throws
    func stop(provider:NEPacketTunnelProvider,removeSettings:Bool) async throws
    func respond(_ request:TransportNativeRequest,provider:NEPacketTunnelProvider) async -> TransportNativeResponse?
}

#if APL_NATIVE_XRAY_CANDIDATE
extension NativeXrayPacketSession:NativeSyntheticProviderSession {
    func start(provider:NEPacketTunnelProvider,request:NativeSyntheticRuntimeRequest) async throws {
        let (route,bytes)=try NativeSyntheticRuntimeFixture.compile(request)
        try await start(provider:provider,route:route,configuration:bytes,descriptor:{ExactLabTUNDescriptor.find(address:"192.0.2.177")})
    }
}
#endif

/// Actual provider entry ownership, only compiled in separate fixture-only
/// binaries. All starts, including ordinary/credential validation, are denied
/// here unless the exact synthetic envelope is present. Never publishes ready.
@MainActor final class NativeSyntheticProviderOwner {
    private var session:(any NativeSyntheticProviderSession)?
    private static var selection=NativeSyntheticEngineSelection()
    private var used=false
    private var retired=false
    private var starting=false
    private var timeout:Task<Void,Never>?
    private var completion:((Error?)->Void)?
    private func finish(_ error:Error?){let c=completion;completion=nil;c?(error)}
    private func failure(_ code:Int)->NSError {NSError(domain:"APLNativeSynthetic",code:code)}
    func start(provider:NEPacketTunnelProvider,options:[String:NSObject]?,completionHandler:@escaping(Error?)->Void) async {
        #if APL_NATIVE_UNIFIED_GO_CANDIDATE
        let supported:Set<TransportProvider> = [.rustXray,.standaloneAWG]
        #elseif APL_NATIVE_XRAY_CANDIDATE
        let supported:Set<TransportProvider> = [.rustXray]
        #else
        let supported:Set<TransportProvider> = [.standaloneAWG]
        #endif
        guard !used,!retired,let request=Self.selection.claim(configuration:(provider.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,options:options,supported:supported) else{completionHandler(failure(1));return}
        used=true;starting=true;completion=completionHandler
        defer{starting=false}
        do {
            let runtime:any NativeSyntheticProviderSession
            switch request.binding.reference.kind.provider {
            case .rustXray:
                #if APL_NATIVE_XRAY_CANDIDATE
                runtime=try NativeXrayPacketSession(owner:request.binding)
                #else
                throw failure(1)
                #endif
            case .standaloneAWG:
                #if APL_NATIVE_AWG_CANDIDATE
                runtime=try NativeAWGPacketSession(owner:request.binding)
                #else
                throw failure(1)
                #endif
            default:throw failure(1)
            }
            session=runtime
            timeout=Task { @MainActor [weak self,weak provider] in
                try? await Task.sleep(nanoseconds:8_000_000_000)
                guard !Task.isCancelled,let self,self.starting else{return}
                self.retired=true;self.finish(self.failure(2));provider?.cancelTunnelWithError(self.failure(2))
                if let provider {try? await self.session?.stop(provider:provider,removeSettings:true)}
            }
            try await runtime.start(provider:provider,request:request)
            timeout?.cancel();timeout=nil
            guard !retired else{throw failure(2)}
            // OS setup completion only, to permit independent fixture probes.
            // This is not a native-ready or successful peer-traffic receipt.
            finish(nil)
        } catch {
            retired=true;timeout?.cancel();timeout=nil
            try? await session?.stop(provider:provider,removeSettings:true)
            finish(failure(3));provider.cancelTunnelWithError(failure(3))
        }
    }
    func stop(provider:NEPacketTunnelProvider) async {
        retired=true;timeout?.cancel();timeout=nil
        finish(failure(4))
        do{try await session?.stop(provider:provider,removeSettings:true)}catch{provider.cancelTunnelWithError(failure(4))}
    }
    func message(_ bytes:Data,provider:NEPacketTunnelProvider) async -> Data? {
        guard !starting,let session,let request=try? TransportNativeCodec.decode(TransportNativeRequest.self,bytes),request.valid else{return nil}
        let response=await session.respond(request,provider:provider)
        return response.flatMap{try? TransportNativeCodec.encode($0)}
    }
}
#endif
