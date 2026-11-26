#if APL_CLOUDKIT_LIVE_QA && APL_CLOUDKIT_ENABLED
import SwiftUI
import CloudKit

@MainActor private final class SyntheticCloudLocalModel: ExclusionCloudLocalModel {
    @Published var manualExclusions = ["qa-alpha.example.com"]
    let smartGraph = SmartExclusionGraph()
    private(set) var applied = 0
    func saveExclusions(_ raw: [String], graph: SmartExclusionGraph?) async -> Bool {
        guard raw == ["qa-beta.example.com","qa-gamma.example.com"],
              graph == smartGraph else { return false }
        applied += 1
        manualExclusions = raw
        return true
    }
}

/// The real production screen, an in-memory local model and two private
/// Development service instances. No owner preference or manager access.
@MainActor struct CloudKitOrdinaryUIQAView: View {
    struct Command: Codable {
        let runID: UUID
        let clientA: UUID
        let clientB: UUID
    }
    struct Receipt: Codable {
        let runID: UUID
        var initialAbsent = false
        var firstUpload = false
        var secondUpload = false
        var localApplied = false
        var cleaned = false
        var recoveryOnly = false
        var failed = false
        let physicalDevices = 1
        let releaseAuthorized = false
    }
    private static let root = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
    private static let input = root.appendingPathComponent("apl-cloudkit-ui-qa-input.json")
    private static let journal = root.appendingPathComponent("apl-cloudkit-ui-qa-journal.json")
    private static let output = root.appendingPathComponent("apl-cloudkit-ui-qa-result.json")
    private static let first = ["qa-alpha.example.com"]
    private static let second = ["qa-beta.example.com","qa-gamma.example.com"]
    @StateObject private var local = SyntheticCloudLocalModel()
    @State private var command: Command?
    @State private var receipt: Receipt?
    @State private var client: ExclusionCloudKitService?
    @State private var showing = false
    @State private var started = false
    @State private var busy = false
    @State private var status = "Preparing synthetic CloudKit UI"
    var body: some View {
        VStack(spacing:16) {
            Text(status)
            if let client, let receipt, !receipt.cleaned, !receipt.failed {
                Button("Open CloudKit UI") { showing = true }.disabled(busy)
                Button("Verify upload and stage second client") { Task { await stageSecond() } }
                    .disabled(busy || receipt.secondUpload)
                Button("Verify apply and clean") { Task { await finish() } }
                    .disabled(busy || !receipt.secondUpload || local.applied != 1)
                Text("Local synthetic list: "+local.manualExclusions.joined(separator:", "))
            }
        }.padding()
        .sheet(isPresented:$showing) {
            if let client { ExclusionCloudSyncView(model:local,qaCloud:client) {} }
        }
        .task { if !started { started=true; await setup() } }
    }
    private func publish(_ r: Receipt) {
        receipt=r
        try? JSONEncoder().encode(r).write(to:Self.output,options:.atomic)
    }
    private func read(_ url:URL)throws->Command {
        let attrs=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard attrs.isRegularFile==true,attrs.isSymbolicLink==false,
              (1...1024).contains(attrs.fileSize ?? 0) else{throw ExclusionSyncError.invalid}
        let c=try JSONDecoder().decode(Command.self,from:Data(contentsOf:url))
        guard Set([c.runID,c.clientA,c.clientB]).count==3 else{throw ExclusionSyncError.invalid}
        return c
    }
    private func failed() {
        if var r=receipt {r.failed=true;publish(r)}
        status="QA stopped; inspect receipt and recover exact journal"
    }
    private func setup()async {
        do {
            let recover=ProcessInfo.processInfo.arguments.contains("--apl-authorized-cloudkit-ui-recovery")
            let c:Command
            if recover {c=try read(Self.journal)}
            else {
                guard !FileManager.default.fileExists(atPath:Self.journal.path) else{throw ExclusionSyncError.invalid}
                c=try read(Self.input);try FileManager.default.removeItem(at:Self.input)
            }
            command=c
            var r=Receipt(runID:c.runID);r.recoveryOnly=recover;publish(r)
            let a=ExclusionCloudKitService(qaRunID:c.runID,qaDeviceID:c.clientA)
            let review=try await a.reviewAccount()
            if recover {
                if try await a.previewRemote(expectedAccount:review) != nil {
                    try await a.qaDeleteSynthetic(expectedAccount:review,
                        expectedDevices:[c.clientA.uuidString.lowercased(),c.clientB.uuidString.lowercased()],
                        expectedDomains:[Self.first,Self.second])
                }
                try FileManager.default.removeItem(at:Self.journal)
                r.cleaned=true;publish(r);status="Recovery complete";return
            }
            guard try await a.previewRemote(expectedAccount:review)==nil else{throw ExclusionSyncError.invalid}
            try JSONEncoder().encode(c).write(to:Self.journal,options:.atomic)
            r.initialAbsent=true;publish(r);client=a
            status="Open CloudKit UI; inspect, upload, confirm, close"
        }catch{failed()}
    }
    private func stageSecond()async {
        guard !busy,let c=command,let a=client,var r=receipt,!r.secondUpload else{return}
        busy=true;defer{busy=false}
        do {
            let account=try await a.reviewAccount()
            guard let (first,tag)=try await a.previewRemote(expectedAccount:account),
                  first.manualDomains==Self.first,first.revision==1,
                  first.deviceID==c.clientA.uuidString.lowercased(),local.applied==0 else{throw ExclusionSyncError.invalid}
            r.firstUpload=true;publish(r)
            let b=ExclusionCloudKitService(qaRunID:c.runID,qaDeviceID:c.clientB)
            let updated=try await b.upload(manualDomains:Self.second,expectedRemote:tag,
                observedRemoteWasAbsent:false,expectedAccount:account)
            guard updated.revision==2,updated.manualDomains==Self.second,
                  updated.deviceID==c.clientB.uuidString.lowercased() else{throw ExclusionSyncError.invalid}
            r.secondUpload=true;publish(r);status="Open CloudKit UI; inspect, apply, close"
        }catch{failed()}
    }
    private func finish()async {
        guard !busy,let c=command,let a=client,var r=receipt,r.secondUpload else{return}
        busy=true;defer{busy=false}
        do {
            let account=try await a.reviewAccount()
            guard local.applied==1,local.manualExclusions==Self.second,
                let (final,_)=try await a.previewRemote(expectedAccount:account),
                final.revision==2,final.manualDomains==Self.second,
                final.deviceID==c.clientB.uuidString.lowercased() else{throw ExclusionSyncError.invalid}
            r.localApplied=true;publish(r)
            try await a.qaDeleteSynthetic(expectedAccount:account,
                expectedDevices:[c.clientA.uuidString.lowercased(),c.clientB.uuidString.lowercased()],
                expectedDomains:[Self.first,Self.second])
            try FileManager.default.removeItem(at:Self.journal)
            r.cleaned=true;publish(r);status="CloudKit UI QA complete"
        }catch{failed()}
    }
}
#endif
