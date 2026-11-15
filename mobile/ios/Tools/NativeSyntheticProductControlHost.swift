// Compile-only host for the isolated unified provider; not included in App.
// No manager creation, preferences mutation, user credentials or ready claim.
import Foundation
import NetworkExtension

private final class SyntheticProductReply: @unchecked Sendable {
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Data?,Error>?
    init(_ c:CheckedContinuation<Data?,Error>){continuation=c}
    func finish(_ result:Result<Data?,Error>){lock.lock();let c=continuation;continuation=nil;lock.unlock();c?.resume(with:result)}
}

@MainActor final class NativeSyntheticProductControlHost {
    enum Failure:Error {case unowned,invalidState,missingReceipt,timeout}
    private static let providerID="ru.arvectum.proxylauncher.lab.productunifiedcompile.PacketTunnel"
    private static let name="APL isolated unified synthetic QA"
    private let manager:NETunnelProviderManager
    private let connection:NETunnelProviderSession
    private let owner:UUID
    let identity:TransportNativeIdentity
    private var options:[String:NSObject]
    private(set) var attempted=false, observedSetup=false, staleRejected=false, drained=false, off=false
    private var busy=false
    init(manager:NETunnelProviderManager,owner:UUID,kind:NativeCredentialRecord.Kind,fixture:Data,localIPv4:UInt32?)throws {
        guard let connection=manager.connection as? NETunnelProviderSession else{throw Failure.unowned}
        self.manager=manager;self.connection=connection;self.owner=owner
        identity = .init(epoch:UUID(),generation:1,provider:kind.providerName)
        let binding=NativeCredentialHandoff.Binding(reference:.init(profileID:UUID(),revision:UUID(),kind:kind),session:identity,selectionNonce:UUID())
        let config=NativeSyntheticRuntimeRequest.configuration(owner:owner)
        var values:[String:NSObject]=config.mapValues{$0 as NSString}
        values[NativeProviderStartRequest.expectedKey]=try TransportNativeCodec.encode(binding) as NSData
        values[NativeSyntheticRuntimeRequest.fixtureKey]=fixture as NSData
        if let localIPv4 {values[NativeSyntheticRuntimeRequest.localKey]=String(localIPv4) as NSString}
        guard NativeSyntheticRuntimeRequest.inspect(configuration:config,options:values,provider:kind.provider) != nil else{throw Failure.invalidState}
        options=values
        guard owned(manager) else{throw Failure.unowned}
    }
    private func owned(_ item:NETunnelProviderManager)->Bool {
        guard let proto=item.protocolConfiguration as? NETunnelProviderProtocol,let config=proto.providerConfiguration,Set(config.keys)==Set(NativeSyntheticRuntimeRequest.configuration(owner:owner).keys) else{return false}
        return proto.providerBundleIdentifier==Self.providerID && item.localizedDescription==Self.name && proto.serverAddress==Self.name && config[NativeProviderStartRequest.modeKey] as? String==NativeSyntheticRuntimeRequest.mode && config[NativeProviderStartRequest.ownerKey] as? String==owner.uuidString && item.isEnabled && !item.isOnDemandEnabled && (item.onDemandRules ?? []).isEmpty
    }
    private var ownsConnection:Bool {owned(manager) && manager.connection === connection}
    private func censusOff()async throws {
        let all:[NETunnelProviderManager]=try await withCheckedThrowingContinuation { c in
            NETunnelProviderManager.loadAllFromPreferences { items,error in
                if let error {c.resume(throwing:error)} else if let items {c.resume(returning:items)} else{c.resume(throwing:Failure.unowned)}
            }
        }
        try Task.checkCancellation()
        guard ownsConnection,connection.status == .disconnected,all.filter({owned($0)}).count==1,
              all.allSatisfy({$0.connection.status == .disconnected && !$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty}) else{throw Failure.unowned}
    }
    /// Only an external trusted harness may attest fresh process quiescence.
    /// Calling this function is outside current authorization.
    func submit(externalQuiescenceConfirmed:Bool)async throws {
        guard !busy,!attempted,externalQuiescenceConfirmed else{throw Failure.invalidState}
        busy=true;defer{busy=false}
        try await censusOff();try Task.checkCancellation()
        attempted=true
        let values=options;options.removeAll()
        try connection.startTunnel(options:values)
    }
    private func exchange(_ request:TransportNativeRequest)async throws -> TransportNativeResponse {
        guard ownsConnection,connection.status == .connected else{throw Failure.unowned}
        let bytes=try TransportNativeCodec.encode(request)
        let data:Data?=try await withCheckedThrowingContinuation { c in
            let gate=SyntheticProductReply(c)
            do{try connection.sendProviderMessage(bytes){gate.finish(.success($0))}}catch{gate.finish(.failure(error))}
            DispatchQueue.global().asyncAfter(deadline:.now()+6){gate.finish(.failure(Failure.timeout))}
        }
        try Task.checkCancellation()
        guard ownsConnection,connection.status == .connected,let data else{throw Failure.missingReceipt}
        let reply=try TransportNativeCodec.decode(TransportNativeResponse.self,data)
        guard reply.matches(request) else{throw Failure.missingReceipt};return reply
    }
    /// Setup-only. Observe .starting after OS readiness, and prove stale
    /// epoch rejection. No assertion about engine/peer readiness is made.
    func observeSetup()async throws {
        guard !busy,attempted,!drained,!off else{throw Failure.invalidState}
        busy=true;defer{busy=false}
        let deadline=ProcessInfo.processInfo.systemUptime+8
        while ownsConnection && connection.status == .connecting && ProcessInfo.processInfo.systemUptime<deadline {try await Task.sleep(nanoseconds:50_000_000)}
        let reply=try await exchange(.init(identity:identity,action:.observe))
        guard reply.state == .starting else{throw Failure.missingReceipt}
        let other=TransportNativeIdentity(epoch:UUID(),generation:identity.generation,provider:identity.provider)
        let stale=try await exchange(.init(identity:other,action:.observe))
        guard stale.state == .rejected else{throw Failure.missingReceipt}
        observedSetup=true;staleRejected=true
    }
    /// Always allow exact cleanup after attempted setup, even if observation
    /// failed. Never infer drain from OS disconnect or a missing response.
    func drainAndReconcile()async throws {
        guard !busy,attempted,!off,ownsConnection else{throw Failure.invalidState}
        busy=true;defer{busy=false}
        if !drained {
            let reply=try await exchange(.init(identity:identity,action:.drain))
            guard reply.state == .drained else{throw Failure.missingReceipt};drained=true
        }
        guard ownsConnection else{throw Failure.unowned}
        if connection.status == .connected {connection.stopVPNTunnel()}
        let deadline=ProcessInfo.processInfo.systemUptime+10
        while ownsConnection && connection.status != .disconnected && ProcessInfo.processInfo.systemUptime<deadline {try await Task.sleep(nanoseconds:100_000_000)}
        try await censusOff();off=true
    }
}
