#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PRODUCT_RUNTIME_REVIEW
#if !APL_NATIVE_AWG_PRODUCT_BRIDGE || !APL_NATIVE_UNIFIED_GO_CANDIDATE || !APL_NATIVE_XRAY_CANDIDATE || !APL_NATIVE_AWG_CANDIDATE || APL_NATIVE_SYNTHETIC_RUNTIME
#error("Runtime review requires unified product drivers, never synthetic mode")
#endif
import Foundation
import NetworkExtension
import Network

/// Separate bounded hardware-review lane. No UI caller, Settings restart,
/// or legacy fallback. OS start completion is setup, not peer readiness.
@MainActor final class NativeProductRuntimeOwner {
    private var used=false,retired=false,starting=false,draining=false
    private var settingsInstalled=false
    private var control=TransportNativeControlState()
    private var awg:NativeAWGProductFlow?
    private var xray:NativeXrayPacketSession?
    private var completion:((Error?)->Void)?
    private var timeout:Task<Void,Never>?
    private var monitor:NWPathMonitor?
    private var baseline:PathSignature?
    private struct PathSignature:Equatable {
        let status:Network.NWPath.Status
        let interfaces:[String]
        let expensive:Bool
        let constrained:Bool
        init(_ path:Network.NWPath){
            status=path.status
            interfaces=path.availableInterfaces.map{$0.name+":"+String(describing:$0.type)+":"+String(path.usesInterfaceType($0.type))}.sorted()
            expensive=path.isExpensive;constrained=path.isConstrained
        }
    }
    private func error(_ code:Int)->NSError{NSError(domain:"APLNativeRuntimeReview",code:code)}
    private func finish(_ failure:Error?){let reply=completion;completion=nil;reply?(failure)}
    func start(provider:NEPacketTunnelProvider,options:[String:NSObject]?,completionHandler:@escaping(Error?)->Void)async{
        guard !used,!retired,let request=NativeRuntimeReviewRequest.inspect(configuration:(provider.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,options:options,enabled:true) else{completionHandler(error(1));return}
        used=true;starting=true;completion=completionHandler
        do {
            try control.bind(request.binding.session,provider:request.binding.reference.kind.providerName)
            let store=try ProfileStore(),handoff=store.makeNativeProviderValidationHandoff()
            let plan=try request.consume(via:handoff,admission:store.nativeRoutingAdmission())
            guard try handoff.authorizes(request.binding),store.nativeRoutingAdmission().permitsSelection else{throw error(1)}
            timeout=Task { @MainActor [weak self,weak provider] in
                do{try await Task.sleep(nanoseconds:45_000_000_000)}catch{return}
                guard let self,let provider,!self.retired else{return}
                self.invalidate(provider:provider,code:2)
                if !self.starting {try? await self.drain(provider:provider,removeSettings:true)}
            }
            let bytes=plan.configuration.withEngineConfiguration{$0}
            switch plan.route {
            case .awg(let route):
                guard NativeExactTunnelDescriptor.interfaces(address:route.ipv4Address)?.isEmpty==true else{throw error(1)}
                let flow=try NativeAWGProductFlow(flow:provider.packetFlow,plan:route,onFailure:{[weak self,weak provider] in
                    Task{@MainActor in if let self,let provider{self.invalidate(provider:provider,code:3)}}
                })
                awg=flow;settingsInstalled=true
                try await provider.setTunnelNetworkSettings(NativeTunnelNetworkSettings.make(route))
                guard !retired,try handoff.authorizes(request.binding),store.nativeRoutingAdmission().permitsSelection else{throw error(1)}
                guard await flow.startWithDeadline(configuration:bytes) else{throw error(3)}
            case .xray(let route):
                let runner=try NativeXrayPacketSession(owner:request.binding)
                xray=runner
                try await runner.startScoped(provider:provider,plan:route,configuration:bytes)
            }
            guard !retired,try handoff.authorizes(request.binding),store.nativeRoutingAdmission().permitsSelection else{throw error(1)}
            starting=false
            let watcher=NWPathMonitor();monitor=watcher
            watcher.pathUpdateHandler={[weak self,weak provider] path in
                let signature=PathSignature(path)
                Task{@MainActor in
                    guard let self,let provider,!self.retired else{return}
                    if signature.status != .satisfied || (self.baseline != nil && self.baseline != signature){self.invalidate(provider:provider,code:4)}
                    else{self.baseline=signature}
                }
            }
            watcher.start(queue:DispatchQueue(label:"apl.native.review.path"))
            finish(nil)
        }catch{
            starting=false
            invalidate(provider:provider,code:3)
            try? await drain(provider:provider,removeSettings:true)
        }
    }
    private func invalidate(provider:NEPacketTunnelProvider,code:Int){
        guard !retired else{return}
        retired=true;awg?.cancelPendingStart();xray?.cancelPendingStart()
        timeout?.cancel();timeout=nil;monitor?.cancel();monitor=nil
        finish(error(code));provider.cancelTunnelWithError(error(code))
    }
    /// A bounded wait is not a drain receipt. Retain ambiguous ownership.
    private func drain(provider:NEPacketTunnelProvider,removeSettings:Bool)async throws{
        guard !starting,!draining else{throw error(5)}
        if control.state == .drained && !settingsInstalled && awg==nil && xray==nil{return}
        draining=true;defer{draining=false}
        if control.state != .draining && control.state != .drained {try control.beginDrain()}
        if let awg {
            guard await awg.stopWithDeadline() else{throw error(5)}
            self.awg=nil
        }
        if let xray {
            try await xray.stop(provider:provider,removeSettings:removeSettings)
            if removeSettings {self.xray=nil}
        }
        if removeSettings && settingsInstalled {try await provider.setTunnelNetworkSettings(nil);settingsInstalled=false}
        if control.state == .draining {try control.finishDrain()}
    }
    func stop(provider:NEPacketTunnelProvider)async{
        retired=true;awg?.cancelPendingStart();xray?.cancelPendingStart();timeout?.cancel();timeout=nil;monitor?.cancel();monitor=nil;finish(error(5))
        let deadline=ProcessInfo.processInfo.systemUptime+6
        while (starting || draining) && ProcessInfo.processInfo.systemUptime<deadline {
            try? await Task.sleep(nanoseconds:50_000_000)
        }
        guard !starting,!draining,used else{return}
        do{try await drain(provider:provider,removeSettings:true)}catch{provider.cancelTunnelWithError(self.error(5))}
    }
    func message(_ bytes:Data,provider:NEPacketTunnelProvider)async->Data?{
        guard let request=try? TransportNativeCodec.decode(TransportNativeRequest.self,bytes),request.valid else{return nil}
        if let rejected=control.rejection(to:request){return try? TransportNativeCodec.encode(rejected)}
        guard (try? control.response(to:request)) != nil else{return nil}
        if request.action == .drain,control.state != .drained {
            retired=true;awg?.cancelPendingStart();xray?.cancelPendingStart();timeout?.cancel();timeout=nil;monitor?.cancel();monitor=nil;finish(error(5))
            guard !starting,!draining else{return try? TransportNativeCodec.encode(TransportNativeResponse(request:request,state:.draining))}
            do{try await drain(provider:provider,removeSettings:false)}catch{return try? TransportNativeCodec.encode(TransportNativeResponse(request:request,state:.failed))}
        }
        if retired && control.state != .drained {return try? TransportNativeCodec.encode(TransportNativeResponse(request:request,state:.draining))}
        guard let response=try? control.response(to:request) else{return nil}
        return try? TransportNativeCodec.encode(response)
    }
}
#endif
