// Separate QA bundle only. Actual product runner, no ProfileStore or owner tickets.
#if APL_ISOLATED_PRODUCT_RUNNER_QA
import Foundation
import NetworkExtension

final class NativeLabPacketTunnelProvider:NEPacketTunnelProvider {
    @MainActor private var runner:NativeXrayPacketSession?
    @MainActor private var consumed=false
    @MainActor private var deadline:Task<Void,Never>?
    override func startTunnel(options:[String:NSObject]?,completionHandler:@escaping(Error?)->Void) {
        Task { @MainActor in
            do {
                guard runner==nil,!consumed,
                    options?["aplNativeSyntheticQA"] as? String=="explicit-lab-v1",
                    options?["aplLabTransport"] as? String=="vless-product-direct",
                    options?["aplFixedWitnessKind"] as? String=="tcp4",
                    let link=options?["aplSyntheticLink"] as? String,link.utf8.count<=4096,
                    let nonce=options?["aplProviderNonce"] as? String,nonce.utf8.count==40,
                    nonce.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{throw NativeLabError.stage(21)}
                let parsed=try VLESSRealityShareLink.parse(link)
                guard parsed.serverHost=="192.168.1.80",parsed.serverPort==39882,
                    parsed.serverName=="example.com" else{throw NativeLabError.stage(22)}
                let record=try NativeCredentialRecord.create(profileID:UUID(),expected:.vlessReality,source:link)
                let candidate=try record.compileFullTunnelCandidate(admission:.tunnelOnly,exactDNSAvailable:true)
                let identity=TransportNativeIdentity(epoch:UUID(),generation:1,provider:"rust-xray")
                let binding=NativeCredentialHandoff.Binding(reference:record.reference,session:identity,selectionNonce:UUID())
                let owned=try NativeXrayPacketSession(owner:binding)
                runner=owned
                deadline=Task { @MainActor [weak self] in
                    do{try await Task.sleep(nanoseconds:20_000_000_000)}catch{return}
                    guard let self,!Task.isCancelled else{return}
                    self.consumed=true;self.runner?.cancelPendingStart()
                    self.cancelTunnelWithError(NativeLabError.stage(26).safeNSError)
                }
                try await owned.startFull(provider:self,candidate:candidate)
                guard !consumed else{throw NativeLabError.stage(27)}
                completionHandler(nil)
            }catch{
                consumed=true;deadline?.cancel();deadline=nil
                if let runner {try? await runner.stop(provider:self,removeSettings:true)}
                completionHandler(NativeLabError.stage(27).safeNSError)
            }
        }
    }
    override func handleAppMessage(_ messageData:Data,completionHandler:((Data?)->Void)?) {
        Task { @MainActor in
            guard messageData==Data("apl-provider-direct-v1".utf8),!consumed,let runner else{completionHandler?(nil);return}
            consumed=true
            do {
                try await runner.stop(provider:self,removeSettings:false)
                let reply=["providerProcess":true,"rustTUNStarted":true,"rustDrainConfirmed":true,
                    "nativeStopConfirmed":true,"fullRouteSyntheticGuard":true,"scopedRouteOnly":false,
                    "witness_tcp4":true,"actualProductRunner":true,"releaseAuthorized":false]
                completionHandler?(try? JSONSerialization.data(withJSONObject:reply,options:.sortedKeys))
            }catch{completionHandler?(nil);self.cancelTunnelWithError(NativeLabError.stage(29).safeNSError)}
        }
    }
    override func stopTunnel(with reason:NEProviderStopReason,completionHandler:@escaping()->Void) {
        Task { @MainActor in
            consumed=true;deadline?.cancel();deadline=nil
            if let runner {try? await runner.stop(provider:self,removeSettings:true)}
            completionHandler()
        }
    }
}
#endif
