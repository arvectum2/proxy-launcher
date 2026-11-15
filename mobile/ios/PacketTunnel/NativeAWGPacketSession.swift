#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_SYNTHETIC_RUNTIME && APL_NATIVE_AWG_CANDIDATE
import Foundation
import NetworkExtension

private final class AWGSessionCompletion: @unchecked Sendable {
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Bool,Never>?
    init(_ c:CheckedContinuation<Bool,Never>){continuation=c}
    func finish(_ ok:Bool){lock.lock();let c=continuation;continuation=nil;lock.unlock();c?.resume(returning:ok)}
}

/// Reuse the reviewed bounded packetFlow pump, not the Xray runtime.
/// Fixed LAN fixture only, no user storage, default routes or DNS.
@MainActor final class NativeAWGPacketSession:NativeSyntheticProviderSession {
    enum Failure:Error {case unsupported,busy,notDrained}
    private let owner:NativeCredentialHandoff.Binding
    private var control=TransportNativeControlState()
    private var pump:AWGPacketFlowPump?
    private var retired=false,starting=false,draining=false,settingsInstalled=false
    private var lifetime:Task<Void,Never>?
    init(owner:NativeCredentialHandoff.Binding)throws {
        guard owner.valid,owner.reference.kind == .amneziaWG1 else{throw Failure.unsupported}
        self.owner=owner;try control.bind(owner.session,provider:"standalone-awg")
    }
    private func bounded(_ action:(@escaping(Bool)->Void)->Void)async -> Bool {
        await withCheckedContinuation { c in
            let completion=AWGSessionCompletion(c)
            action{completion.finish($0)}
            DispatchQueue.global().asyncAfter(deadline:.now()+5){completion.finish(false)}
        }
    }
    func start(provider:NEPacketTunnelProvider,request:NativeSyntheticRuntimeRequest) async throws {
        guard !retired,!starting,!draining,pump==nil,request.binding==owner,let local=request.localIPv4 else{throw Failure.unsupported}
        starting=true;defer{starting=false}
        do {
            let settings=NEPacketTunnelNetworkSettings(tunnelRemoteAddress:"192.168.1.80")
            let v4=NEIPv4Settings(addresses:["192.0.2.1"],subnetMasks:["255.255.255.255"])
            v4.includedRoutes=[NEIPv4Route(destinationAddress:"192.0.2.2",subnetMask:"255.255.255.255")];settings.ipv4Settings=v4
            let v6=NEIPv6Settings(addresses:["2001:db8::1"],networkPrefixLengths:[128])
            v6.includedRoutes=[NEIPv6Route(destinationAddress:"2001:db8::2",networkPrefixLength:128)];settings.ipv6Settings=v6;settings.mtu=1280
            settingsInstalled=true;try await provider.setTunnelNetworkSettings(settings)
            guard !retired else{throw Failure.busy}
            let bridge=AWGPacketFlowPump(flow:provider.packetFlow){[weak self,weak provider] in
                Task { @MainActor in
                    self?.retired=true;self?.control.fail();provider?.cancelTunnelWithError(NSError(domain:"APLNativeAWG",code:1))
                }
            }
            pump=bridge
            let ok=await bounded{done in bridge.start(keys:request.fixture,localIPv4:local,listen:39890,peer:39891,completion:done)}
            guard ok,!retired else{throw Failure.busy}
            lifetime=Task { @MainActor [weak self,weak provider] in
                try? await Task.sleep(nanoseconds:20_000_000_000)
                guard !Task.isCancelled,let self,!self.retired else{return}
                self.retired=true;self.control.fail();provider?.cancelTunnelWithError(NSError(domain:"APLNativeAWG",code:2))
            }
            // Queue/pump started, not handshake or peer readiness.
        } catch {
            starting=false;retired=true;control.fail();try? await stop(provider:provider,removeSettings:true);throw error
        }
    }
    func stop(provider:NEPacketTunnelProvider,removeSettings:Bool) async throws {
        retired=true;guard !starting,!draining else{control.fail();throw Failure.busy}
        draining=true;defer{draining=false};lifetime?.cancel();lifetime=nil
        if control.state != .failed && control.state != .drained {try control.beginDrain()}
        do {
            if let pump {guard await bounded({done in pump.stop(completion:done)}) else{throw Failure.notDrained};self.pump=nil}
            if removeSettings && settingsInstalled {try await provider.setTunnelNetworkSettings(nil);settingsInstalled=false}
            if control.state == .draining {try control.finishDrain()}
        }catch{control.fail();throw error}
    }
    func respond(_ request:TransportNativeRequest,provider:NEPacketTunnelProvider) async -> TransportNativeResponse? {
        if let rejected=control.rejection(to:request){return rejected}
        guard (try? control.response(to:request)) != nil else{return nil}
        if request.action == .drain && control.state != .drained {
            do{try await stop(provider:provider,removeSettings:false)}catch{control.fail();provider.cancelTunnelWithError(NSError(domain:"APLNativeAWG",code:3))}
        }
        return try? control.response(to:request)
    }
}
#endif
