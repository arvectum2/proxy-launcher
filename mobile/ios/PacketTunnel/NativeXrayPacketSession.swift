#if (DEBUG || APL_NATIVE_PRODUCT_RUNTIME) && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_XRAY_CANDIDATE
import Foundation
import NetworkExtension
import tun2proxy

/// Owned Xray runner. Only explicit experimental review lanes, never shipping starts.
@MainActor final class NativeXrayPacketSession {
    enum Failure:Error {case unsupported, busy, notDrained}
    private let owner:NativeCredentialHandoff.Binding
    private let driver=NativeXrayRuntimeDriver.shared
    private let queue=DispatchQueue(label:"apl.native.xray.candidate.runner")
    private let exitGate=TunnelEngineExitGate()
    private var control=TransportNativeControlState()
    private var attemptedXray=false
    private var submittedRust=false
    private var starting=false
    private var draining=false
    private var retired=false
    private var settingsInstalled=false
    private var lifetime:Task<Void,Never>?
    init(owner:NativeCredentialHandoff.Binding)throws {
        guard owner.valid,owner.reference.kind.provider == .rustXray else{throw Failure.unsupported}
        self.owner=owner
        try control.bind(owner.session,provider:"rust-xray")
    }
#if APL_NATIVE_PRODUCT_RUNTIME
#if !APL_NATIVE_EXACT_DNS || APL_NATIVE_PRODUCT_RUNTIME_REVIEW || APL_NATIVE_SYNTHETIC_RUNTIME
#error("The product runtime requires exact DNS and cannot include review or synthetic runtime")
#endif
    func startFull(provider:NEPacketTunnelProvider,candidate:NativeFullTunnelCandidate)async throws {
        let plan=candidate.route
        guard candidate.reference==owner.reference,plan.provider == .rustXray,
              candidate.exactDNSRequired,plan.excludedRoutes.isEmpty,!plan.dnsServers.isEmpty,
              NativeExactTunnelDescriptor.interfaces(address:plan.ipv4Address)?.isEmpty==true,
              NativeExactTunnelDescriptor.interfaces(address:plan.ipv6Address)?.isEmpty==true else{throw Failure.unsupported}
        try await startOwned(provider:provider,route:candidate.validation,
            configuration:candidate.configuration.withEngineConfiguration{$0},
            planSettings:NativeTunnelNetworkSettings.make(plan),mtu:UInt16(plan.mtu),exactDNS:true,
            descriptor:{NativeExactTunnelDescriptor.find(address:plan.ipv4Address,ipv6:plan.ipv6Address)})
    }
#else
    /// Actual route settings for synthetic test destinations only. No DNS,
    /// default routes, excluded routes, or endpoint-wide application bypass.
    private func settings(_ route:NativeValidationRoute)throws -> NEPacketTunnelNetworkSettings {
        guard route.remoteAddress=="192.168.1.80" else{throw Failure.unsupported}
        let dual:Bool
        switch route {
        case .wireGuard(let p):guard owner.reference.kind == .wireGuard,p.remotePort==39881 else{throw Failure.unsupported};dual=true
        case .vlessTCP4(let p):guard owner.reference.kind == .vlessReality,p.remotePort==39882 else{throw Failure.unsupported};dual=false
        }
        let s=NEPacketTunnelNetworkSettings(tunnelRemoteAddress:route.remoteAddress)
        let v4=NEIPv4Settings(addresses:["192.0.2.177"],subnetMasks:["255.255.255.255"])
        v4.includedRoutes=[NEIPv4Route(destinationAddress:"198.51.100.77",subnetMask:"255.255.255.255")];s.ipv4Settings=v4
        if dual {let v6=NEIPv6Settings(addresses:["2001:db8:177::2"],networkPrefixLengths:[128]);v6.includedRoutes=[NEIPv6Route(destinationAddress:"2001:db8:77::77",networkPrefixLength:128)];s.ipv6Settings=v6}
        s.mtu=dual ? 1280 : 1500;return s
    }
    /// No authorization or caller is provided yet. A future accepted harness
    /// must supply synthetic configuration and an exact OS-owned descriptor.
    func start(provider:NEPacketTunnelProvider,route:NativeValidationRoute,configuration:Data,descriptor:()->Int32?) async throws {
        try await startOwned(provider:provider,route:route,configuration:configuration,planSettings:try settings(route),mtu:owner.reference.kind == .wireGuard ? 1280:1500,descriptor:descriptor)
    }
#if APL_NATIVE_PRODUCT_RUNTIME_REVIEW
    /// User-configured Xray peer, exact independent probe route only.
    /// Full default/DNS capture requires a separate accepted DNS implementation.
    func startScoped(provider:NEPacketTunnelProvider,plan:NativeRuntimeReviewPlan.XrayProbeRoute,configuration:Data)async throws {
        guard plan.validation.provider == .rustXray,(1280...1500).contains(plan.mtu),
              (plan.localIPv6==nil)==(plan.targetIPv6==nil),
              NativeExactTunnelDescriptor.interfaces(address:plan.localIPv4)?.isEmpty==true else{throw Failure.unsupported}
        let settings=NEPacketTunnelNetworkSettings(tunnelRemoteAddress:plan.validation.remoteAddress)
        let v4=NEIPv4Settings(addresses:[plan.localIPv4],subnetMasks:["255.255.255.255"])
        v4.includedRoutes=[NEIPv4Route(destinationAddress:plan.targetIPv4,subnetMask:"255.255.255.255")]
        v4.excludedRoutes=[];settings.ipv4Settings=v4;settings.mtu=NSNumber(value:plan.mtu)
        var exactDNS=false
        if let local6=plan.localIPv6,let target6=plan.targetIPv6 {
#if APL_NATIVE_EXACT_DNS
            guard owner.reference.kind == .vlessReality,NativeExactTunnelDescriptor.interfaces(address:local6)?.isEmpty==true else{throw Failure.unsupported}
            let v6=NEIPv6Settings(addresses:[local6],networkPrefixLengths:[128])
            v6.includedRoutes=[NEIPv6Route(destinationAddress:target6,networkPrefixLength:128)]
            v6.excludedRoutes=[];settings.ipv6Settings=v6;exactDNS=true
#else
            _=local6;_=target6;throw Failure.unsupported
#endif
        }
        try await startOwned(provider:provider,route:plan.validation,configuration:configuration,planSettings:settings,mtu:UInt16(plan.mtu),exactDNS:exactDNS,descriptor:{NativeExactTunnelDescriptor.find(address:plan.localIPv4,ipv6:plan.localIPv6)})
    }
#if APL_NATIVE_EXACT_DNS
    func startWireGuardFull(provider:NEPacketTunnelProvider,plan:NativeTunnelRoutePlan,configuration:Data)async throws {
        guard owner.reference.kind == .wireGuard,plan.provider == .rustXray,plan.excludedRoutes.isEmpty,
              !plan.dnsServers.isEmpty,NativeExactTunnelDescriptor.interfaces(address:plan.ipv4Address)?.isEmpty==true,
              NativeExactTunnelDescriptor.interfaces(address:plan.ipv6Address)?.isEmpty==true else{throw Failure.unsupported}
        try await startOwned(provider:provider,route:.wireGuard(plan),configuration:configuration,planSettings:NativeTunnelNetworkSettings.make(plan),mtu:UInt16(plan.mtu),exactDNS:true,descriptor:{NativeExactTunnelDescriptor.find(address:plan.ipv4Address,ipv6:plan.ipv6Address)})
    }
#endif
#endif
#endif
    private func startOwned(provider:NEPacketTunnelProvider,route:NativeValidationRoute,configuration:Data,planSettings:NEPacketTunnelNetworkSettings,mtu:UInt16,exactDNS:Bool=false,descriptor:()->Int32?) async throws {
        guard !retired,!starting,!draining,!attemptedXray,!submittedRust else{throw Failure.busy}
        starting=true;defer{starting=false}
        do {
            try driver.validate(route:route,configuration:configuration)
            // Treat even a failed settings application as ambiguous.
            settingsInstalled=true
            try await provider.setTunnelNetworkSettings(planSettings)
            try Task.checkCancellation()
            guard !retired,let fd=descriptor() else{throw Failure.unsupported}
            let handoff=try XraySocksHandoffPlan.prepare(tunFD:Int(fd),socksPort:39879,dnsBypass:[],exactDNS:exactDNS)
            attemptedXray=true
            try driver.startXray(owner:owner,route:route,configuration:configuration)
            try Task.checkCancellation()
            guard !retired else{throw Failure.busy}
            let token=exitGate.begin(),gate=exitGate
            submittedRust=true
            queue.async { [weak provider,weak self] in
                guard gate.isRunning(token) else{return}
                _=handoff.tun2proxyArguments.withCString{tun2proxy_run_with_cli_args($0,mtu,true)}
                guard gate.markUnexpectedExit(token) else{return}
                Task { @MainActor in
                    guard gate.shouldCancelTunnel(token),let self else{return}
                    self.retired=true;self.control.fail()
                    provider?.cancelTunnelWithError(NSError(domain:"APLNativeRuntime",code:1))
                }
            }
#if !APL_NATIVE_PRODUCT_RUNTIME
            lifetime=Task { @MainActor [weak self,weak provider] in
                try? await Task.sleep(nanoseconds:20_000_000_000)
                guard !Task.isCancelled,let self,!self.retired else{return}
                self.retired=true;self.control.fail()
                provider?.cancelTunnelWithError(NSError(domain:"APLNativeRuntime",code:3))
            }
#endif
            // No ready receipt: queue submission is not independent peer or
            // native readiness evidence. A future accepted probe must supply it.
        } catch {
            retired=true;control.fail();starting=false
            try? await stop(provider:provider,removeSettings:true)
            throw error
        }
    }
    func cancelPendingStart(){retired=true;exitGate.invalidate()}
    func stop(provider:NEPacketTunnelProvider,removeSettings:Bool) async throws {
        retired=true
        guard !starting,!draining else{control.fail();throw Failure.busy}
        draining=true;defer{draining=false}
        lifetime?.cancel();lifetime=nil
        if control.state != .failed && control.state != .drained {try control.beginDrain()}
        exitGate.invalidate()
        do {
            if submittedRust {try await NativeXrayRuntimeDriver.drainOwnedRustRunner(queue:queue);submittedRust=false}
            if attemptedXray {try driver.stopOwnedXray(owner:owner);attemptedXray=false}
            if removeSettings && settingsInstalled {try await provider.setTunnelNetworkSettings(nil);settingsInstalled=false}
            if control.state == .draining {try control.finishDrain()}
        } catch {control.fail();throw error}
    }
    func respond(_ request:TransportNativeRequest,provider:NEPacketTunnelProvider) async -> TransportNativeResponse? {
        if let rejected=control.rejection(to:request){return rejected}
        guard (try? control.response(to:request)) != nil else{return nil}
        if request.action == .drain && control.state != .drained {
            do{try await stop(provider:provider,removeSettings:false)}catch{control.fail();provider.cancelTunnelWithError(NSError(domain:"APLNativeRuntime",code:2))}
        }
        return try? control.response(to:request)
    }
}
#endif
