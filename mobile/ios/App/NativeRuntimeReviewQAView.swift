#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PRODUCT_RUNTIME_REVIEW && APL_NATIVE_RUNTIME_QA_HARNESS && APL_NATIVE_PERSISTENT_LIBRARY && !targetEnvironment(simulator)
import SwiftUI
import Foundation
import Network
import CryptoKit

/// A separate explicitly launched operator harness, never a normal VPN screen.
private struct NativeRuntimeQACommand:Decodable {
    enum Action:String,Codable {case prepareManager,readManager,run,removeManager,offControl}
    let schema:Int
    let requestID:UUID
    let owner:UUID
    let reference:NativeCredentialRecord.Reference
    let action:Action
    let scope:NativeCredentialHandoff.RuntimeScope?
    let probe:String?
    let nonce:String?
    let mode:String?
    var valid:Bool {
        guard schema==1,requestID != owner else{return false}
        if action == .offControl {
            return reference.kind == .wireGuard && scope == .wireGuardFull &&
                ["udp4","udp6","dnsWire4"].contains(probe ?? "") && mode=="observe-off" &&
                nonce?.utf8.count==40 && nonce?.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})==true
        }
        if action != .run {return scope==nil && probe==nil && nonce==nil && mode==nil}
        if mode=="peer-loss" {
#if APL_NATIVE_EXACT_DNS
            return reference.kind == .wireGuard && scope == .wireGuardFull &&
                ["udp4","udp6"].contains(probe ?? "") &&
                nonce?.utf8.count==40 && nonce?.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})==true
#else
            return false
#endif
        }
        guard let probe,let nonce,let mode,(["tcp4","tcp6","udp4","udp6"].contains(probe) || (probe=="dns4" && mode=="positive" && ((reference.kind == .amneziaWG1 && scope==nil) || (reference.kind == .wireGuard && scope == .wireGuardFull)))),
              nonce.utf8.count==(reference.kind == .amneziaWG1 ? 48:40),
              nonce.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{return false}
#if !APL_NATIVE_EXACT_DNS
        guard scope==nil else{return false}
#endif
        switch reference.kind {
        case .wireGuard:return (scope == .wireGuardFull || (scope==nil && probe=="tcp4")) && ["positive","wrong-key"].contains(mode)
        case .vlessReality:return (scope == .vlessDatagrams || (scope==nil && probe=="tcp4")) && ["positive","wrong-key"].contains(mode)
        case .amneziaWG1:return scope==nil && ["positive","wrong-key","wrong-psk"].contains(mode)
        }
    }
    var postLossNonce:String? {
        guard mode=="peer-loss",let nonce else{return nil}
        return String(SHA256.hash(data:Data(("APL-QA-POST-LOSS:"+nonce).utf8)).map{String(format:"%02x",$0)}.joined().prefix(40))
    }
    var probeIPv4:String? {reference.kind == .amneziaWG1 || scope == .wireGuardFull ? nil:"198.51.100.77"}
    var probeIPv6:String? {scope == .vlessDatagrams ? "2001:db8:77::77":nil}
    static func readAndConsume(_ url:URL)throws->Self {
        let a=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard a.isRegularFile==true,a.isSymbolicLink==false,let count=a.fileSize,(1...4096).contains(count) else{throw NativeValidationDispatch.Failure.invalidState}
        let f=try FileHandle(forReadingFrom:url);defer{try? f.close()}
        let data=try f.read(upToCount:4097) ?? Data()
        guard data.count<=4096,let raw=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              Set(raw.keys).isSubset(of:["schema","requestID","owner","reference","action","scope","probe","nonce","mode"]),
              let ref=raw["reference"] as? [String:Any],Set(ref.keys)==["profileID","revision","kind"] else{throw NativeValidationDispatch.Failure.invalidState}
        let command=try JSONDecoder().decode(Self.self,from:data)
        guard command.valid else{throw NativeValidationDispatch.Failure.invalidState}
        try FileManager.default.removeItem(at:url)
        return command
    }
}
private struct NativeRuntimeQAReferenceReceipt:Encodable {
    let schema=1
    let reference:NativeCredentialRecord.Reference
}
private struct NativeRuntimeQALossObservation:Encodable {
    let firstStart:Double
    let firstEnd:Double
    let secondStart:Double
    let secondEnd:Double
    let secondChallengeSHA256:String
    let secondResponseSHA256:String?
}
private struct NativeRuntimeQAReceipt:Encodable {
    let schema=1
    let requestID:UUID
    let owner:UUID
    let reference:NativeCredentialRecord.Reference
    let action:NativeRuntimeQACommand.Action
    let scope:NativeCredentialHandoff.RuntimeScope?
    let probe:String?
    let mode:String?
    let setup:[NativeReviewControlExchange]
    let drain:NativeReviewControlExchange?
    let probeAttempted:Bool
    let responseSHA256:String?
    let managerReadback:Bool
    let osOff:Bool
    var loss:NativeRuntimeQALossObservation?=nil
    let independentWitnessRequired=true
    let releaseAuthorized=false
}

/// Failed operations are diagnostic evidence only, never a successful receipt.
private struct NativeRuntimeQAFailureReceipt:Encodable {
    let schema=1
    let requestID:UUID
    let action:NativeRuntimeQACommand.Action
    let stage:String
    let errorType:String
    let errorCode:Int
    let drainConfirmed:Bool
    let releaseAuthorized=false
}
@MainActor struct NativeRuntimeReviewQAView:View {
    static var enabled:Bool {ProcessInfo.processInfo.arguments.contains("-aplNativeRuntimeReviewQA")}
    @StateObject private var vpn=VPNController()
    @Environment(\.scenePhase) private var phase
    @State private var command:NativeRuntimeQACommand?
    @State private var confirmed=false
    @State private var busy=false
    @State private var used=false
    @State private var generation=UUID()
    @State private var status="Not armed. No VPN action."
    @State private var fixtureConfirmed=false
    @State private var showLibrary=false
    @State private var fixtureModel:AppViewModel?
    private var directory:URL {FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]}
    var body:some View {
        VStack(spacing:20) {
            Text("Native runtime QA").font(.headline)
            Text(status).font(.footnote)
            if !used && !busy && command==nil {
                Toggle("Disposable test environment confirmed",isOn:$fixtureConfirmed)
                Button("Open disposable fixture library"){Task{await openLibrary()}}.disabled(!fixtureConfirmed)
                Button("Export selected fixture ID"){Task{await exportReference()}}.disabled(!fixtureConfirmed)
                Button("Arm one local command"){arm()}
            }
            if let command,!used,!busy {
                Text(command.action.rawValue+" · "+command.reference.kind.rawValue)
                Toggle("Disposable device and independent peer verified",isOn:$confirmed)
                Button("Execute once"){Task{await execute()}}.disabled(!confirmed)
                Button("Disarm"){invalidate()}
            }
        }.padding()
        .sheet(isPresented:$showLibrary,onDismiss:{fixtureModel=nil}){if let fixtureModel {NativePersistentProfilesView(model:fixtureModel)}}
        .onChange(of:phase){if $0 == .background {invalidate()}}
    }
    private func openLibrary()async {
        guard fixtureConfirmed,!busy,!used,command==nil else{return}
        busy=true;defer{busy=false}
        let token=generation
        do {
            guard try await vpn.nativeRuntimeQACanOpenFixtureLibrary(),generation==token else{throw NativeValidationDispatch.Failure.unownedManager}
            fixtureConfirmed=false;fixtureModel=AppViewModel();showLibrary=true
        }catch{status="Existing data or manager detected. Fixture library blocked."}
    }
    private func exportReference()async {
        guard fixtureConfirmed,!busy,!used,command==nil else{return}
        busy=true;defer{busy=false}
        let token=generation
        do {
            let reference=try await vpn.nativeRuntimeQAFixtureReference()
            guard generation==token,!Task.isCancelled else{throw NativeValidationDispatch.Failure.invalidState}
            let name="apl-native-runtime-qa-ref-"+UUID().uuidString+".json"
            try JSONEncoder().encode(NativeRuntimeQAReferenceReceipt(reference:reference)).write(to:directory.appendingPathComponent(name),options:[.withoutOverwriting,.completeFileProtection])
            fixtureConfirmed=false;status="Selected fixture metadata saved: "+name
        }catch{status="Selected isolated fixture not available."}
    }
    private func arm(){
        guard !busy,!used,!showLibrary,command==nil else{return}
        do{command=try NativeRuntimeQACommand.readAndConsume(directory.appendingPathComponent("apl-native-runtime-qa-command.json"));confirmed=false;status="One command consumed. External approval still required."}
        catch{status="Command rejected. No VPN action."}
    }
    private func invalidate(){generation=UUID();command=nil;confirmed=false;fixtureConfirmed=false;showLibrary=false;if !busy {status="Disarmed. No automatic restart."}}
    private func execute()async {
        guard Self.enabled,!used,!busy,confirmed,let command else{return}
        let token=generation
        used=true;busy=true;self.command=nil;confirmed=false
        defer{busy=false}
        func authorized()->Bool {generation==token && !Task.isCancelled}
        var drain:NativeReviewControlExchange?
        var stage="authorization"
        do {
            guard authorized() else{throw NativeValidationDispatch.Failure.invalidState}
            if command.action == .offControl {
                stage="off-control-before"
                _=try await vpn.readNativeRuntimeQAManager(owner:command.owner,reference:command.reference,authorized:authorized)
                guard authorized() else{throw NativeValidationDispatch.Failure.invalidState}
                stage="off-control-probe"
                _=await NativeRuntimeQAProbe.exchange(command)
                guard authorized() else{throw NativeValidationDispatch.Failure.invalidState}
                stage="off-control-after"
                _=try await vpn.readNativeRuntimeQAManager(owner:command.owner,reference:command.reference,authorized:authorized)
                guard authorized() else{throw NativeValidationDispatch.Failure.invalidState}
                try save(.init(requestID:command.requestID,owner:command.owner,reference:command.reference,action:.offControl,scope:command.scope,probe:command.probe,mode:command.mode,setup:[],drain:nil,probeAttempted:true,responseSHA256:nil,managerReadback:true,osOff:true))
                status="OFF control attempted. External packet visibility must be verified."
                return
            }
            if command.action != .run {
                stage="manager"
                if command.action == .readManager {
                    let disconnect=try await vpn.readNativeRuntimeQAManager(owner:command.owner,reference:command.reference,authorized:authorized)
                    let name="apl-native-runtime-qa-disconnect-"+command.requestID.uuidString+".txt"
                    try Data(disconnect.utf8).write(to:directory.appendingPathComponent(name),options:[.withoutOverwriting,.completeFileProtection])
                } else {
                try await vpn.performNativeRuntimeQAManager(owner:command.owner,reference:command.reference,remove:command.action == .removeManager,authorized:authorized)
                }
                guard authorized() else{throw NativeValidationDispatch.Failure.invalidState}
                try save(.init(requestID:command.requestID,owner:command.owner,reference:command.reference,action:command.action,scope:nil,probe:nil,mode:nil,setup:[],drain:nil,probeAttempted:false,responseSHA256:nil,managerReadback:true,osOff:true))
                status="Manager operation read back. No tunnel started."
                return
            }
            stage="submission"
            try await vpn.submitNativeRuntimeReview(reference:command.reference,owner:command.owner,probeIPv4:command.probeIPv4,scope:command.scope,probeIPv6:command.probeIPv6,stillAuthorized:authorized)
            stage="setup"
            let setup=try await vpn.observeNativeRuntimeReviewSetup(owner:command.owner)
            guard authorized() else{throw NativeValidationDispatch.Failure.invalidState}
            stage="probe"
            let firstStart=Date().timeIntervalSince1970
            let hash=await NativeRuntimeQAProbe.exchange(command)
            let firstEnd=Date().timeIntervalSince1970
            guard authorized() else{throw NativeValidationDispatch.Failure.invalidState}
            var loss:NativeRuntimeQALossObservation?
            if let next=command.postLossNonce {
                guard hash != nil else{throw NativeValidationDispatch.Failure.invalidState}
                stage="peer-loss-wait"
                // The independent peer stops after its exact first witness.
                // A timer alone is never evidence of loss; host verifies cut time.
                try await Task.sleep(nanoseconds:8_000_000_000)
                guard authorized() else{throw NativeValidationDispatch.Failure.invalidState}
                stage="peer-loss-probe"
                let secondStart=Date().timeIntervalSince1970
                let second=await NativeRuntimeQAProbe.exchange(command,postLoss:true)
                let secondEnd=Date().timeIntervalSince1970
                loss=NativeRuntimeQALossObservation(firstStart:firstStart,firstEnd:firstEnd,secondStart:secondStart,secondEnd:secondEnd,secondChallengeSHA256:SHA256.hash(data:Data(next.utf8)).map{String(format:"%02x",$0)}.joined(),secondResponseSHA256:second)
                guard authorized() else{throw NativeValidationDispatch.Failure.invalidState}
            }
            stage="drain"
            drain=try await vpn.reconcileNativeRuntimeReview(owner:command.owner)
            guard authorized(),let drain else{throw NativeValidationDispatch.Failure.invalidState}
            stage="receipt"
            try save(.init(requestID:command.requestID,owner:command.owner,reference:command.reference,action:.run,scope:command.scope,probe:command.probe,mode:command.mode,setup:setup,drain:drain,probeAttempted:true,responseSHA256:hash,managerReadback:true,osOff:true,loss:loss))
            status="Host observation saved. Independent peer and capture verification required."
        }catch {
            // Only the exact submitted owner can be drained. A missing receipt
            // is unconfirmed, never permission to stop or remove another VPN.
            if command.action == .run && drain==nil {
                drain=try? await vpn.reconcileNativeRuntimeReview(owner:command.owner)
            }
            // Never persist localized descriptions or error userInfo (may contain secrets).
            let failure=NativeRuntimeQAFailureReceipt(requestID:command.requestID,action:command.action,stage:stage,errorType:String(describing:type(of:error)),errorCode:(error as NSError).code,drainConfirmed:drain != nil)
            let file=directory.appendingPathComponent("apl-native-runtime-qa-failure-"+command.requestID.uuidString+".json")
            try? JSONEncoder().encode(failure).write(to:file,options:[.withoutOverwriting,.completeFileProtection])
            status=drain != nil ? "Test incomplete; owned drain and OS-off reconciled." : "State unconfirmed. No automatic retry or manager removal."
        }
    }
    private func save(_ receipt:NativeRuntimeQAReceipt)throws {
        let url=directory.appendingPathComponent("apl-native-runtime-qa-receipt-"+receipt.requestID.uuidString+".json")
        try JSONEncoder().encode(receipt).write(to:url,options:[.withoutOverwriting,.completeFileProtection])
    }
}
private final class NativeRuntimeQAProbeReply: @unchecked Sendable {
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Bool,Never>?
    init(_ c:CheckedContinuation<Bool,Never>){continuation=c}
    func finish(_ value:Bool){lock.lock();let c=continuation;continuation=nil;lock.unlock();c?.resume(returning:value)}
}
private enum NativeRuntimeQAProbe {
    /// Fixed documentation-address witnesses, one bounded exchange, no DNS,
    /// redirects, arbitrary destinations, fallback, or owner data.
    static func exchange(_ command:NativeRuntimeQACommand,postLoss:Bool=false)async->String? {
        guard command.valid,(command.action == .run || command.action == .offControl),let probe=command.probe,let nonce=(postLoss ? command.postLossNonce : command.nonce) else{return nil}
        let awg=command.reference.kind == .amneziaWG1,udp=probe.hasPrefix("udp") || probe=="dnsWire4",v4=probe.hasSuffix("4")
        // Only one generated reserved-domain name, with no arbitrary hostname.
        let host=probe=="dnsWire4" ? "192.0.2.53" : probe=="dns4" ? nonce+".apl-nativeqa.test." : (awg ? (v4 ? "192.0.2.2":"2001:db8::2") : (v4 ? "198.51.100.77":"2001:db8:77::77"))
        let expected=Data(((awg ? "APL:":"APL_RECEIPT:")+nonce).utf8)
        let http = !awg && !udp
        let request:Data
        if probe=="dnsWire4" {
            // Fixed documentation-address DNS positive-control attempt.
            // No system resolver or user DNS name, no arbitrary destination.
            var query=Data([0x41,0x50,0x01,0,0,1,0,0,0,0,0,0])
            for label in [nonce,"apl-nativeqa","test"] {
                query.append(UInt8(label.utf8.count));query.append(contentsOf:label.utf8)
            }
            query.append(contentsOf:[0,0,1,0,1]);request=query
        } else if http {
            let authority=v4 ? host:"["+host+"]"
            request=Data(("GET /"+nonce+" HTTP/1.1\r\nHost: "+authority+":39883\r\nConnection: close\r\n\r\n").utf8)
        } else {request=Data(((awg ? "":"APL_UDP:")+nonce).utf8)}
        let port:NWEndpoint.Port=probe=="dnsWire4" ? 53 : (awg ? 39892:39883)
        let c=NWConnection(host:NWEndpoint.Host(host),port:port,using:udp ? .udp:.tcp)
        let q=DispatchQueue(label:"apl.native.runtime.qa.probe")
        let matched=await withCheckedContinuation { (continuation:CheckedContinuation<Bool,Never>) in
            let once=NativeRuntimeQAProbeReply(continuation)
            @Sendable func receiveHTTP(_ old:Data) {
                guard old.count<8192 else{once.finish(false);return}
                c.receive(minimumIncompleteLength:1,maximumLength:8192-old.count){data,_,complete,error in
                    guard error==nil else{once.finish(false);return}
                    let value=old+(data ?? Data())
                    if complete {
                        guard let separator=value.range(of:Data("\r\n\r\n".utf8)) else{once.finish(false);return}
                        let headers=String(decoding:value[..<separator.lowerBound],as:UTF8.self)
                        once.finish((headers.hasPrefix("HTTP/1.1 200 ") || headers.hasPrefix("HTTP/1.0 200 ")) && Data(value[separator.upperBound...])==expected)
                    } else {receiveHTTP(value)}
                }
            }
            c.stateUpdateHandler={state in
                switch state {
                case .ready:
                    c.stateUpdateHandler=nil
                    c.send(content:request,completion:.contentProcessed{error in
                        guard error==nil else{once.finish(false);return}
                        if udp {c.receiveMessage{data,_,_,failure in once.finish(failure==nil && data==expected)}}
                        else if http {receiveHTTP(Data())}
                        else {c.receive(minimumIncompleteLength:expected.count,maximumLength:expected.count+1){data,_,_,failure in once.finish(failure==nil && data==expected)}}
                    })
                case .failed,.cancelled:once.finish(false)
                default:break
                }
            }
            q.asyncAfter(deadline:.now()+(probe=="dns4" ? 8:4)){once.finish(false);c.cancel()}
            c.start(queue:q)
        }
        c.cancel()
        return matched ? SHA256.hash(data:expected).map{String(format:"%02x",$0)}.joined():nil
    }
}
#endif
