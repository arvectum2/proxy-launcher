// Future supervised QA only. Not in production project. Never invoked by build.
import Foundation
import NetworkExtension

struct UnifiedManagerCommand:Codable,Equatable {
    enum Action:String,Codable {case prepare,remove}
    let schema:Int
    let requestID:UUID
    let owner:UUID
    let action:Action
    var valid:Bool {schema == 1 && requestID != owner}
}
struct UnifiedManagerReceipt:Codable {
    let schema:Int
    let requestID:UUID
    let owner:UUID
    let action:UnifiedManagerCommand.Action
    let matched:Int
    let allVisibleOff:Bool
}

@MainActor enum UnifiedManagerLifecycle {
    static let providerID="ru.arvectum.proxylauncher.lab.productunifiedcompile.PacketTunnel"
    static let name="APL isolated unified synthetic QA"
    enum Failure:Error {case invalid,unsafeCensus,unconfirmed}
    static func matches(_ item:NETunnelProviderManager,owner:UUID)->Bool {
        guard let proto=item.protocolConfiguration as? NETunnelProviderProtocol,
              let config=proto.providerConfiguration,
              Set(config.keys)==Set(NativeSyntheticRuntimeRequest.configuration(owner:owner).keys) else{return false}
        return proto.providerBundleIdentifier==providerID && item.localizedDescription==name && proto.serverAddress==name && config[NativeProviderStartRequest.modeKey] as? String==NativeSyntheticRuntimeRequest.mode && config[NativeProviderStartRequest.ownerKey] as? String==owner.uuidString && item.isEnabled && !item.isOnDemandEnabled && (item.onDemandRules ?? []).isEmpty && proto.username==nil && proto.passwordReference==nil && proto.identityReference==nil && proto.identityData==nil && proto.identityDataPassword==nil && proto.proxySettings==nil && !proto.includeAllNetworks && !proto.enforceRoutes
    }
    static func related(_ item:NETunnelProviderManager)->Bool {
        let p=item.protocolConfiguration as? NETunnelProviderProtocol
        return p?.providerBundleIdentifier==providerID || item.localizedDescription==name || p?.serverAddress==name
    }
    static func census()async throws->[NETunnelProviderManager] {
        try await withCheckedThrowingContinuation { c in
            NETunnelProviderManager.loadAllFromPreferences { items,error in
                if let error {c.resume(throwing:error)} else if let items {c.resume(returning:items)} else {c.resume(throwing:Failure.unsafeCensus)}
            }
        }
    }
    static func allOff(_ items:[NETunnelProviderManager])->Bool {
        items.allSatisfy{$0.connection.status == .disconnected && !$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty}
    }
    static func perform(_ command:UnifiedManagerCommand,authorized:()->Bool)async throws->UnifiedManagerReceipt {
        guard command.valid,authorized() else{throw Failure.invalid}
        let before=try await census();try Task.checkCancellation()
        guard authorized(),allOff(before) else{throw Failure.unsafeCensus}
        let lab=before.filter(related)
        switch command.action {
        case .prepare:
            // Never adopt, edit or replace any existing manager, including a stale lab.
            guard lab.isEmpty else{throw Failure.unsafeCensus}
            let item=NETunnelProviderManager(),proto=NETunnelProviderProtocol()
            proto.providerBundleIdentifier=providerID;proto.serverAddress=name
            proto.includeAllNetworks=false;proto.enforceRoutes=false;proto.proxySettings=nil
            proto.providerConfiguration=NativeSyntheticRuntimeRequest.configuration(owner:command.owner)
            item.protocolConfiguration=proto;item.localizedDescription=name
            item.isEnabled=true;item.isOnDemandEnabled=false;item.onDemandRules=[]
            guard authorized(),matches(item,owner:command.owner) else{throw Failure.invalid}
            try await item.saveToPreferences()
        case .remove:
            guard lab.count==1,let item=lab.first,matches(item,owner:command.owner),item.connection.status == .disconnected,authorized() else{throw Failure.unsafeCensus}
            // No stop or removal of a running/ambiguous/foreign manager.
            try await item.removeFromPreferences()
        }
        // A write may have persisted even if callback failed or authorization
        // was lost. Never retry or roll back automatically; report ambiguity.
        let after=try await census();let related=after.filter(Self.related)
        let expected=command.action == .prepare ? 1:0
        guard authorized(),allOff(after),related.count==expected,related.allSatisfy({matches($0,owner:command.owner)}) else{throw Failure.unconfirmed}
        return .init(schema:1,requestID:command.requestID,owner:command.owner,action:command.action,matched:related.count,allVisibleOff:true)
    }
}
