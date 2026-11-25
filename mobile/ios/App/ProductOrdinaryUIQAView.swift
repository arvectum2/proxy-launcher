#if APL_PRODUCT_UI_QA && APL_PRODUCT_OWNER_QA && APL_NATIVE_PRODUCT_RUNTIME
import Foundation
import SwiftUI
import NetworkExtension
import CryptoKit

// Diagnostic container only. The screens inside it are the real ordinary UI.
// This lane is isolated from both production and the earlier owner QA stores.
@MainActor private enum ProductUIQA {
    struct Input:Decodable {let runID:UUID;let fixture:String;let nonce:String}
    struct Journal:Codable {
        let runID:UUID
        let owner:UUID
        let baseline:[String:Bool]
        let configurationDigest:String
    }
    struct Context {
        let input:Input
        let journal:Journal
        let preferences:UserDefaults
    }
    static let domain="ru.arvectum.proxylauncher.ios.synthetic-ui-prefs"
    static var dir:URL {FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]}
    static var journalURL:URL {dir.appendingPathComponent("apl-product-ui-qa-journal.json")}
    static var peerReadyURL:URL {dir.appendingPathComponent("apl-product-ui-qa-peer-ready.json")}
    static var resultURL:URL {dir.appendingPathComponent("apl-product-ui-qa-result.json")}
    static func write(_ receipt:[String:Any]) {
        if let bytes=try? JSONSerialization.data(withJSONObject:receipt,options:.sortedKeys) {
            try? bytes.write(to:resultURL,options:.atomic)
        }
    }
    static func digest(_ record:NativeCredentialRecord)throws->String {
        let bytes=try record.compile().0.withEngineConfiguration{$0}
        return SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    }
    static func setup()async throws->Context {
        let url=dir.appendingPathComponent("apl-product-ui-qa-input.json")
        let attrs=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard attrs.isRegularFile==true,attrs.isSymbolicLink==false,(1...8192).contains(attrs.fileSize ?? 0),
            !FileManager.default.fileExists(atPath:journalURL.path),
            !FileManager.default.fileExists(atPath:peerReadyURL.path) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        let bytes=try Data(contentsOf:url)
        guard bytes.count<=8192 else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        let input=try JSONDecoder().decode(Input.self,from:bytes)
        try FileManager.default.removeItem(at:url)
        guard ScopedTCPWitness.validNonce(input.nonce) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        let link=try VLESSRealityShareLink.parse(input.fixture)
        guard link.serverHost=="192.168.1.80",link.serverPort==39882,link.serverName=="example.com" else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        let store=try ProfileStore(),catalog=store.makeNativeCredentialCatalog()
        let (original,legacy)=try catalog.reviewState()
        guard original==NativeCredentialCatalogReader.Snapshot.empty,legacy.isEmpty,store.qaUIStoreIsEmpty(),
            try NativeCredentialKeychain(purpose:.handoff).handoffAccountsForValidation().isEmpty,
            try ProxySubscriptionStore().list().isEmpty,
            let preferences=UserDefaults(suiteName:domain),
            (preferences.persistentDomain(forName:domain) ?? [:]).isEmpty else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        let baseline=try await VPNController().qaOffCensus()
        let record=try NativeCredentialRecord.create(profileID:UUID(),expected:.vlessReality,source:input.fixture)
        let journal=Journal(runID:input.runID,owner:UUID(),baseline:baseline,configurationDigest:try digest(record))
        try JSONEncoder().encode(journal).write(to:journalURL,options:.atomic)
        try store.qaInstallSyntheticOwner(journal.owner)
        preferences.set(true,forKey:"setupGuideSeen.v1")
        return Context(input:input,journal:journal,preferences:preferences)
    }
    static func checkRevision(_ ref:NativeCredentialRecord.Reference,expected:String,allowMissing:Bool=false)throws {
        guard ref.kind == .vlessReality else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        let repo=NativeCredentialRepository(items:NativeCredentialKeychain(purpose:.revision))
        if let record=try repo.read(ref) {
            guard try digest(record)==expected else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        } else if !allowMissing {throw NativeCredentialReceiver.Failure.invalidIdentity}
    }
    static func cleanup(_ journal:Journal,vpn:VPNController)async throws {
        let store=try ProfileStore(),catalog=store.makeNativeCredentialCatalog()
        let owner=try store.nativeProductOwner()
        guard owner==nil || owner==journal.owner,store.listProfiles().isEmpty,
            try ProxySubscriptionStore().list().isEmpty else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        try await vpn.qaStopOwnedManager(owner:journal.owner)
        try await vpn.qaRemoveManager(owner:journal.owner,baseline:journal.baseline)
        let snapshot=try catalog.reader.snapshot()
        let pending=(snapshot.pendingInsert.map{[$0]} ?? [])+(snapshot.pendingRestore ?? [])
        let refs=Set(snapshot.current+snapshot.retired+pending)
        guard refs.count<=1 else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        for ref in refs {try checkRevision(ref,expected:journal.configurationDigest,allowMissing:!snapshot.current.contains(ref))}
        let handoff=NativeCredentialKeychain(purpose:.handoff)
        let accounts=try handoff.handoffAccountsForValidation()
        guard accounts.count<=1 else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        for account in accounts {_ = try handoff.remove(account:account)}
        guard try handoff.handoffAccountsForValidation().isEmpty else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        store.clearNativeProductSelection()
        if snapshot.pendingInsert != nil {try catalog.reconcilePendingInsert()}
        if snapshot.pendingRestore != nil {try catalog.reconcilePendingRestore(vpnInactive:{true})}
        for ref in snapshot.current {try catalog.remove(ref)}
        try catalog.reconcileRetired()
        try NativeCredentialCatalogKeychain().qaRemoveEmptyCatalog()
        if owner != nil {try store.qaRemoveSyntheticOwner(journal.owner)}
        TelemetryStore().clear()
        store.qaUIClearIsolatedPreferences()
        guard store.qaUIStoreIsEmpty() else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        UserDefaults(suiteName:domain)?.removePersistentDomain(forName:domain)
        if FileManager.default.fileExists(atPath:peerReadyURL.path) {try FileManager.default.removeItem(at:peerReadyURL)}
        try FileManager.default.removeItem(at:journalURL)
    }
}

@MainActor struct ProductOrdinaryUIQAView:View {
    @State private var context:ProductUIQA.Context?
    @State private var status="Explicit UI QA command required"
    @State private var started=false
    var body:some View {
        Group {
            if let context {ProductOrdinaryUIQASession(context:context)}
            else {Text(status).padding()}
        }
        .task {
            guard !started else{return};started=true
            let args=ProcessInfo.processInfo.arguments
            do {
                if args.contains("--apl-authorized-product-ui-cleanup") {
                    let journal=try JSONDecoder().decode(ProductUIQA.Journal.self,from:Data(contentsOf:ProductUIQA.journalURL))
                    try await ProductUIQA.cleanup(journal,vpn:VPNController())
                    ProductUIQA.write(["runID":journal.runID.uuidString,"cleaned":true,"recoveryOnly":true,"releaseAuthorized":false])
                    status="Recovery complete"
                } else if args.contains("--apl-authorized-product-ui-qa") {
                    context=try await ProductUIQA.setup()
                }
            }catch{
                status="QA setup or recovery failed"
                ProductUIQA.write(["cleaned":false,"errorCode":(error as NSError).code,"releaseAuthorized":false])
            }
        }
    }
}

@MainActor private struct ProductOrdinaryUIQASession:View {
    let context:ProductUIQA.Context
    @StateObject private var model=AppViewModel()
    @State private var showImport=true
    @State private var imported=false
    @State private var selected=false
    @State private var peerReady=false
    @State private var witnessStarted=false
    @State private var exact=false
    @State private var connected=false
    @State private var disconnectedByHome=false
    @State private var cleaned=false
    @State private var busy=false
    @State private var failure=false
    @State private var counters:[String:Int]=[:]
    @State private var ticketConsumed=false
    @State private var banner="Review and save the synthetic VLESS profile"

    var body:some View {
        Group {
            if cleaned {Text("UI QA cleaned").padding()}
            else {
                VStack(spacing:0) {
                    HStack {
                        Text(banner).font(.caption2)
                        Spacer()
                        Button("QA Cleanup") {Task{await finish()}}
                            .disabled(busy || model.vpn.isConnectedOrConnecting || model.vpn.status == .disconnecting)
                    }.padding(6)
                    ContentView()
                        .disabled(busy || (selected && !peerReady))
                        .environmentObject(model)
                        .defaultAppStorage(context.preferences)
                }
                .sheet(isPresented:$showImport) {
                    ProxyImportView(initialSource:context.input.fixture)
                        .environmentObject(model)
                        .defaultAppStorage(context.preferences)
                }
                .onChange(of:model.nativeLibraryOverview){_ in refreshEvidence()}
                .onChange(of:model.vpn.status){_ in Task{await observeVPN()}}
                .task(id:selected){if selected {await waitForPeer()}}
            }
        }
        .onAppear{publish()}
    }
    private func publish(){
        ProductUIQA.write([
            "runID":context.input.runID.uuidString,
            "actualOrdinaryUI":true,"importedUnselected":imported,
            "selectedExplicitly":selected,"peerReady":peerReady,"homeStarts":model.qaUIToggleStarts,
            "homeStops":model.qaUIToggleStops,"connected":connected,
            "ticketConsumed":ticketConsumed,"exactWitness":exact,
            "disconnectedByHome":disconnectedByHome,"cleaned":cleaned,
            "failed":failure,"counters":counters,"releaseAuthorized":false
        ])
    }
    private func refreshEvidence(){
        guard !cleaned,!busy,!failure else{return}
        do {
            let store=try ProfileStore(),snapshot=try store.makeNativeCredentialCatalog().reader.snapshot()
            guard !snapshot.hasPendingWrite,snapshot.current.count<=1,snapshot.retired.isEmpty else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            if let ref=snapshot.current.first {
                try ProductUIQA.checkRevision(ref,expected:context.journal.configurationDigest)
                if let selection=try store.nativeProductSelection() {
                    guard imported,selection.reference==ref,snapshot.selected==ref,
                        selection.nonce==snapshot.selectionNonce else{throw NativeCredentialReceiver.Failure.invalidIdentity}
                    selected=true
                    if !connected && !peerReady{banner="Selected — waiting for independent peer"}
                } else if snapshot.selected==nil {
                    imported=true;banner="Imported — select the VLESS row"
                }
            }
            publish()
        }catch{failure=true;banner="QA evidence invalid; cleanup required";publish()}
    }
    private func waitForPeer()async {
        guard !peerReady,!failure,!cleaned else{return}
        struct Ready:Decodable {let runID:UUID;let ready:Bool}
        let deadline=Date().addingTimeInterval(35)
        while !Task.isCancelled && Date()<deadline && !cleaned {
            if FileManager.default.fileExists(atPath:ProductUIQA.peerReadyURL.path) {
                do {
                    let attrs=try ProductUIQA.peerReadyURL.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                    guard attrs.isRegularFile==true,attrs.isSymbolicLink==false,(1...512).contains(attrs.fileSize ?? 0) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
                    let value=try JSONDecoder().decode(Ready.self,from:Data(contentsOf:ProductUIQA.peerReadyURL))
                    guard value.runID==context.input.runID,value.ready else{throw NativeCredentialReceiver.Failure.invalidIdentity}
                    try FileManager.default.removeItem(at:ProductUIQA.peerReadyURL)
                    peerReady=true;banner="Peer ready — tap Home Connect";publish();return
                }catch{failure=true;banner="Peer marker invalid";publish();return}
            }
            do{try await Task.sleep(nanoseconds:500_000_000)}catch{return}
        }
        if !Task.isCancelled && !cleaned {failure=true;banner="Peer unavailable — QA Cleanup";publish()}
    }
    private func observeVPN()async {
        guard !cleaned,!failure else{return}
        if model.vpn.status == .connected && !witnessStarted {
            witnessStarted=true
            do {
                refreshEvidence()
                guard !failure,imported,selected,peerReady,model.qaUIToggleStarts==1,
                    model.qaUIToggleStops==0,model.vpn.qaLaunch?.ticket.purpose == .productStart else{throw NativeCredentialReceiver.Failure.invalidIdentity}
                connected=true
                ticketConsumed=try NativeCredentialKeychain(purpose:.handoff).handoffAccountsForValidation().isEmpty
                guard ticketConsumed else{throw NativeCredentialReceiver.Failure.invalidIdentity}
                banner="Connected — checking fixed TCP witness";publish()
                let nonce=context.input.nonce
                let result=await Task.detached(priority:.userInitiated){ScopedTCPWitness.run(nonce)}.value
                counters=result.counters
                exact=result.exact && model.vpn.status == .connected
                banner=exact ? "Receipt PASS — tap Home Disconnect" : "Receipt failed — disconnect and cleanup"
                publish()
            }catch{failure=true;banner="QA witness gate failed";publish()}
        } else if connected && (model.vpn.status == .disconnected || model.vpn.status == .invalid) {
            disconnectedByHome=exact && model.qaUIToggleStarts==1 && model.qaUIToggleStops==1
            banner=disconnectedByHome ? "Home disconnect confirmed — QA Cleanup" : "Ended without complete Home proof — cleanup"
            publish()
        }
    }
    private func finish()async {
        guard !busy,!cleaned,!model.vpn.isConnectedOrConnecting,model.vpn.status != .disconnecting else{return}
        busy=true
        do {
            try await ProductUIQA.cleanup(context.journal,vpn:model.vpn)
            cleaned=true
        }catch{failure=true;banner="Cleanup blocked; recover exact QA journal"}
        busy=false;publish()
    }
}
#endif
