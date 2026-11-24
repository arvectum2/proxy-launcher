#if APL_PRODUCT_OWNER_QA && APL_NATIVE_PRODUCT_RUNTIME
import Foundation
import SwiftUI
import NetworkExtension

final class ProductOwnerQAMessageGate:@unchecked Sendable {
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Data?,Never>?
    init(_ c:CheckedContinuation<Data?,Never>){continuation=c}
    func finish(_ data:Data?){
        lock.lock();let c=continuation;continuation=nil;lock.unlock()
        c?.resume(returning:data)
    }
}

@MainActor struct ProductOwnerQAView:View {
    @StateObject private var vpn=VPNController()
    @State private var started=false
    @State private var status="QA only — no owner credential changes"
    private struct Input:Decodable {let runID:UUID;let fixture:String;let nonce:String}
    private struct Journal:Codable {
        let runID:UUID
        let reference:NativeCredentialRecord.Reference
        let owner:UUID
        let baseline:[String:Bool]
    }
    private var dir:URL {FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]}
    private var journal:URL {dir.appendingPathComponent("apl-product-owner-qa-journal.json")}
    private func write(_ result:[String:Any]){
        if let data=try? JSONSerialization.data(withJSONObject:result,options:.sortedKeys){
            try? data.write(to:dir.appendingPathComponent("apl-product-owner-qa-result.json"),options:.atomic)
        }
    }
    var body:some View {
        VStack(spacing:12){Text("APL product owner QA").font(.headline);Text(status)}
            .task {
                guard !started else{return};started=true
                if ProcessInfo.processInfo.arguments.contains("--apl-authorized-product-owner-qa"){await run()}
                else if ProcessInfo.processInfo.arguments.contains("--apl-authorized-product-owner-cleanup"){await recover()}
            }
    }
    private func recover()async {
        do {
            let j=try JSONDecoder().decode(Journal.self,from:Data(contentsOf:journal))
            try await cleanup(j)
            write(["runID":j.runID.uuidString,"cleaned":true,"recoveryOnly":true,"releaseAuthorized":false])
        }catch{write(["cleaned":false,"recoveryOnly":true,"releaseAuthorized":false])}
    }
    private func run()async {
        var receipt:[String:Any]=["releaseAuthorized":false,"cleaned":false]
        var phase="input"
        var saved:Journal?
        do {
            let input=dir.appendingPathComponent("apl-product-owner-qa-input.json")
            let attrs=try input.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard attrs.isRegularFile==true,attrs.isSymbolicLink==false,(1...8192).contains(attrs.fileSize ?? 0),
                  !FileManager.default.fileExists(atPath:journal.path) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            let data=try Data(contentsOf:input)
            guard data.count<=8192 else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            let command=try JSONDecoder().decode(Input.self,from:data)
            try FileManager.default.removeItem(at:input)
            receipt["runID"]=command.runID.uuidString
            guard ScopedTCPWitness.validNonce(command.nonce) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            let link=try VLESSRealityShareLink.parse(command.fixture)
            guard link.serverHost=="192.168.1.80",link.serverPort==39882,link.serverName=="example.com" else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            phase="baseline"
            let store=try ProfileStore(),catalog=store.makeNativeCredentialCatalog()
            let (original,legacy)=try catalog.reviewState()
            let handoff=NativeCredentialKeychain(purpose:.handoff)
            guard original==NativeCredentialCatalogReader.Snapshot.empty,
                  try handoff.handoffAccountsForValidation().isEmpty,
                  try store.nativeProductOwner()==nil,try store.nativeProductSelection()==nil,
                  store.nativeRoutingAdmission().permitsSelection else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            let baseline=try await vpn.qaOffCensus()
            let record=try NativeCredentialRecord.create(profileID:UUID(),expected:.vlessReality,source:command.fixture)
            let owner=UUID()
            let entry=Journal(runID:command.runID,reference:record.reference,owner:owner,baseline:baseline)
            try JSONEncoder().encode(entry).write(to:journal,options:.atomic);saved=entry
            phase="catalog"
            try store.qaInstallSyntheticOwner(owner)
            try catalog.save(record,select:true,expected:original,expectedLegacy:legacy)
            try store.selectNativeProduct(record.reference)
            phase="connect"
            status="Starting actual VPNController"
            try await vpn.connect()
            guard let launch=vpn.qaLaunch else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            receipt["ticketIssued"]=launch.ticket.purpose == .productStart
            for _ in 0..<100 {
                vpn.qaRefresh()
                if vpn.status == .connected {break}
                try await Task.sleep(nanoseconds:100_000_000)
            }
            vpn.qaRefresh()
            receipt["connected"]=vpn.status == .connected
            guard vpn.status == .connected else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            phase="probe"
            receipt["ticketConsumed"]=try handoff.handoffAccountsForValidation().isEmpty
            let nonce=command.nonce
            let result=await Task.detached(priority:.userInitiated){ScopedTCPWitness.run(nonce)}.value
            receipt["counters"]=result.counters
            vpn.qaRefresh()
            receipt["receipt"]=result.exact && vpn.status == .connected
            phase="drain"
            receipt["nativeDrain"]=try await vpn.qaDrain()
            receipt["actualProductOwner"]=true
        }catch{
            receipt["failurePhase"]=phase
            receipt["errorCode"]=(error as NSError).code
        }
        if let saved {
            do{try await cleanup(saved);receipt["cleaned"]=true}
            catch{receipt["cleanupBlocked"]=true}
        }
        write(receipt)
        status=(receipt["cleaned"] as? Bool)==true ? "QA finished, cleaned" : "QA stopped; inspect receipt"
    }
    private func cleanup(_ j:Journal)async throws {
        let store=try ProfileStore(),catalog=store.makeNativeCredentialCatalog()
        let owner=try store.nativeProductOwner()
        guard owner==nil || owner==j.owner else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        try await vpn.qaStopOwnedManager(owner:j.owner)
        try await vpn.qaRemoveManager(owner:j.owner,baseline:j.baseline)
        let snap=try catalog.reader.snapshot()
        guard snap.current.allSatisfy({$0==j.reference}),snap.retired.allSatisfy({$0==j.reference}),
              snap.pendingInsert==nil || snap.pendingInsert==j.reference,snap.pendingRestore==nil else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        let handoff=NativeCredentialKeychain(purpose:.handoff)
        // Dedicated empty-at-baseline service; only this journal can own a ticket.
        let accounts=try handoff.handoffAccountsForValidation()
        guard accounts.count<=1 else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        for account in accounts {_=try handoff.remove(account:account)}
        guard try handoff.handoffAccountsForValidation().isEmpty else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        store.clearNativeProductSelection()
        if snap.pendingInsert==j.reference {try catalog.reconcilePendingInsert()}
        if snap.current==[j.reference]{try catalog.remove(j.reference)}
        try catalog.reconcileRetired()
        try NativeCredentialCatalogKeychain().qaRemoveEmptyCatalog()
        if owner != nil {try store.qaRemoveSyntheticOwner(j.owner)}
        TelemetryStore().clear()
        try FileManager.default.removeItem(at:journal)
    }
}
#endif
