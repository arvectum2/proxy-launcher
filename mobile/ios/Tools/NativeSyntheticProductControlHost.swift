// Compile-only host for the isolated unified provider; not included in App.
// No manager creation, preferences mutation, user credentials or ready claim.
import Foundation
import NetworkExtension
import Network
import CryptoKit

private final class SyntheticProductReply: @unchecked Sendable {
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Data?,Error>?
    init(_ c:CheckedContinuation<Data?,Error>){continuation=c}
    func finish(_ result:Result<Data?,Error>){lock.lock();let c=continuation;continuation=nil;lock.unlock();c?.resume(with:result)}
}

private final class SyntheticNoRedirect:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
}

struct UnifiedSyntheticHostInput:Decodable,CustomStringConvertible,CustomReflectable {
    let runID:UUID;let owner:UUID;let identity:TransportNativeIdentity
    let kind:NativeCredentialRecord.Kind;let probe:String;let mode:String
    let nonce:String;let fixture:Data;let localIPv4:UInt32?
    var description:String {"UnifiedSyntheticHostInput(redacted)"}
    var customMirror:Mirror {Mirror(self,children:[])}
    var valid:Bool {
        let probes=kind == .vlessReality ? ["tcp4"]:["tcp4","tcp6","udp4","udp6"]
        let modes=kind == .amneziaWG1 ? ["positive","wrong-key","wrong-psk"]:["positive","wrong-key"]
        return identity.valid && identity.generation==1 && identity.provider==kind.providerName && probes.contains(probe) && modes.contains(mode) && nonce.utf8.count==(kind == .amneziaWG1 ? 48:40) && nonce.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}
    }
}
struct UnifiedSyntheticHostReceipt:Codable {
    struct Exchange:Codable {let request:TransportNativeRequest;let response:TransportNativeResponse}
    let schema:Int;let runID:UUID;let owner:UUID;let identity:TransportNativeIdentity
    let fixtureSHA256:String;let probe:String;let mode:String
    let exchanges:[Exchange];let responseSHA256:String?;let probeAttempted:Bool;let osOff:Bool
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
    private let runID:UUID,fixtureSHA256:String,probeKind:String,mode:String,kind:NativeCredentialRecord.Kind
    private var challenge:String
    private var exchanges:[UnifiedSyntheticHostReceipt.Exchange]=[]
    private var probeAttempted=false,responseSHA256:String?
    private static func hex(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    init(manager:NETunnelProviderManager,input:UnifiedSyntheticHostInput)throws {
        guard input.valid else{throw Failure.invalidState}
        let owner=input.owner,kind=input.kind,fixture=input.fixture,localIPv4=input.localIPv4
        self.kind=kind;runID=input.runID;fixtureSHA256=Self.hex(fixture);probeKind=input.probe;mode=input.mode;challenge=input.nonce
        guard let connection=manager.connection as? NETunnelProviderSession else{throw Failure.unowned}
        self.manager=manager;self.connection=connection;self.owner=owner
        identity=input.identity
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
        guard reply.matches(request),exchanges.count<8 else{throw Failure.missingReceipt}
        exchanges.append(.init(request:request,response:reply));return reply
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
    /// One fixed synthetic request only; no arbitrary URL, DNS or proxy.
    /// The response hash is a host-side observation, not peer evidence.
    func probe()async throws {
        guard !busy,observedSetup,staleRejected,!drained,!off,!probeAttempted,ownsConnection,connection.status == .connected else{throw Failure.invalidState}
        busy=true;defer{busy=false};probeAttempted=true
        let nonce=challenge;challenge=""
        let awg=kind == .amneziaWG1,udp=probeKind.hasPrefix("udp"),v4=probeKind.hasSuffix("4")
        let host=awg ? (v4 ? "192.0.2.2":"2001:db8::2"):(v4 ? "198.51.100.77":"2001:db8:77::77")
        let expected=Data(((awg ? "APL:":"APL_RECEIPT:")+nonce).utf8)
        var reply:Data?
        if awg || udp {
            let c=NWConnection(host:NWEndpoint.Host(host),port:awg ? 39892:39883,using:udp ? .udp:.tcp)
            let q=DispatchQueue(label:"apl.unified.synthetic.probe")
            let request=Data(((awg ? "":"APL_UDP:")+nonce).utf8)
            reply=try? await withCheckedThrowingContinuation { continuation in
                let once=SyntheticProductReply(continuation)
                c.stateUpdateHandler={state in
                    switch state {
                    case .ready:
                        c.stateUpdateHandler=nil
                        c.send(content:request,completion:.contentProcessed{error in
                            guard error==nil else{once.finish(.success(nil));return}
                            if udp {c.receiveMessage{data,_,_,error in once.finish(.success(error==nil ? data:nil))}}
                            else {c.receive(minimumIncompleteLength:expected.count,maximumLength:expected.count){data,_,_,error in once.finish(.success(error==nil ? data:nil))}}
                        })
                    case .failed,.cancelled:once.finish(.success(nil))
                    default:break
                    }
                }
                q.asyncAfter(deadline:.now()+4){once.finish(.success(nil));c.cancel()};c.start(queue:q)
            }
            c.cancel()
        } else {
            let cfg=URLSessionConfiguration.ephemeral;cfg.timeoutIntervalForRequest=4;cfg.timeoutIntervalForResource=5;cfg.connectionProxyDictionary=[:];cfg.urlCache=nil;cfg.httpCookieStorage=nil
            let session=URLSession(configuration:cfg,delegate:SyntheticNoRedirect(),delegateQueue:nil)
            defer{session.invalidateAndCancel()}
            if let url=URL(string:"http://"+(v4 ? host:"["+host+"]")+":39883/"+nonce),let (data,response)=try? await session.data(from:url),(response as? HTTPURLResponse)?.statusCode==200 {reply=data}
        }
        try Task.checkCancellation();guard ownsConnection,connection.status == .connected else{throw Failure.unowned}
        if reply==expected {responseSHA256=Self.hex(expected)}
    }
    func receipt()throws->UnifiedSyntheticHostReceipt {
        guard !busy,attempted,observedSetup,staleRejected,probeAttempted,drained,off else{throw Failure.missingReceipt}
        return .init(schema:1,runID:runID,owner:owner,identity:identity,fixtureSHA256:fixtureSHA256,probe:probeKind,mode:mode,exchanges:exchanges,responseSHA256:responseSHA256,probeAttempted:probeAttempted,osOff:off)
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
