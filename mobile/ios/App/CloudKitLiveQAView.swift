#if APL_CLOUDKIT_LIVE_QA && APL_CLOUDKIT_ENABLED
import CloudKit
import SwiftUI

/// Explicit one-shot QA; never constructs the ordinary model or reads its data.
@MainActor struct CloudKitLiveQAView: View {
    private struct Command: Codable {
        let runID: UUID
        let clientA: UUID
        let clientB: UUID
    }
    private struct Receipt: Codable {
        let runID: UUID
        var accountAvailable = false
        var initialAbsent = false
        var firstUpload = false
        var secondRead = false
        var secondUpload = false
        var staleRejected = false
        var changedTag = false
        var previewDiff = false
        var exactFinal = false
        var cleaned = false
        var errorCode: Int?
        var recoveryOnly = false
        let physicalDevices = 1
        let releaseAuthorized = false
    }
    @State private var started = false
    @State private var status = "Explicit CloudKit QA required"
    private static let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private static let input = root.appendingPathComponent("apl-cloudkit-live-qa-input.json")
    private static let journal = root.appendingPathComponent("apl-cloudkit-live-qa-journal.json")
    private static let output = root.appendingPathComponent("apl-cloudkit-live-qa-result.json")
    private static let first = ["qa-alpha.example.com"]
    private static let second = ["qa-beta.example.com", "qa-gamma.example.com"]

    var body: some View {
        Text(status).padding().task {
            guard !started else { return }; started = true
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--apl-authorized-cloudkit-live-qa") { await run(recovery: false) }
            else if args.contains("--apl-authorized-cloudkit-live-recovery") { await run(recovery: true) }
        }
    }
    private func read(_ url: URL) throws -> Command {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink == false,
              (1...1024).contains(values.fileSize ?? 0) else { throw ExclusionSyncError.invalid }
        let command = try JSONDecoder().decode(Command.self, from: Data(contentsOf:url))
        guard Set([command.runID,command.clientA,command.clientB]).count == 3 else { throw ExclusionSyncError.invalid }
        return command
    }
    private func write(_ receipt: Receipt) {
        try? JSONEncoder().encode(receipt).write(to: Self.output, options: .atomic)
    }
    private func run(recovery: Bool) async {
        var receipt: Receipt?
        do {
            let command: Command
            if recovery {
                command = try read(Self.journal)
            } else {
                guard !FileManager.default.fileExists(atPath: Self.journal.path) else { throw ExclusionSyncError.invalid }
                command = try read(Self.input)
                try FileManager.default.removeItem(at: Self.input)
            }
            var result = Receipt(runID: command.runID)
            result.recoveryOnly = recovery
            receipt = result; write(result)
            let a = ExclusionCloudKitService(qaRunID: command.runID, qaDeviceID: command.clientA)
            let b = ExclusionCloudKitService(qaRunID: command.runID, qaDeviceID: command.clientB)
            let deviceA = command.clientA.uuidString.lowercased(), deviceB = command.clientB.uuidString.lowercased()
            let account = try await a.reviewAccount()
            result.accountAvailable = true; receipt = result; write(result)
            if !recovery {
                guard try await a.previewRemote(expectedAccount: account) == nil else { throw ExclusionSyncError.invalid }
                result.initialAbsent = true
                // Persist exact synthetic IDs before any cloud write.
                try JSONEncoder().encode(command).write(to: Self.journal, options: .atomic)
                let first = try await a.upload(manualDomains: Self.first, expectedRemote: nil,
                    observedRemoteWasAbsent: true, expectedAccount: account)
                guard first.revision == 1, first.deviceID == deviceA, first.manualDomains == Self.first else { throw ExclusionSyncError.invalid }
                result.firstUpload = true; receipt = result; write(result)
                guard let (seen, stale) = try await b.previewRemote(expectedAccount: account),
                      seen == first else { throw ExclusionSyncError.invalid }
                result.secondRead = true
                let diff = try ExclusionSyncContract.preview(local: Self.second, remote: seen)
                guard diff.toAdd == Self.first, diff.toRemove == Self.second else { throw ExclusionSyncError.invalid }
                result.previewDiff = true
                let updated = try await b.upload(manualDomains: Self.second, expectedRemote: stale,
                    observedRemoteWasAbsent: false, expectedAccount: account)
                guard updated.revision == 2, updated.deviceID == deviceB, updated.manualDomains == Self.second else { throw ExclusionSyncError.invalid }
                result.secondUpload = true; receipt = result; write(result)
                do {
                    _ = try await a.upload(manualDomains: Self.first, expectedRemote: stale,
                        observedRemoteWasAbsent: false, expectedAccount: account)
                    throw ExclusionSyncError.invalid
                } catch ExclusionCloudKitFailure.requiresRemotePreview {
                    result.staleRejected = true
                }
                guard let (final, record) = try await a.previewRemote(expectedAccount: account),
                      final == updated, let tag = record.recordChangeTag,
                      let oldTag = stale.recordChangeTag, !tag.isEmpty, tag != oldTag else { throw ExclusionSyncError.invalid }
                result.changedTag = true; result.exactFinal = true; receipt = result; write(result)
            }
            try await a.qaDeleteSynthetic(expectedAccount: account, expectedDevices: [deviceA,deviceB],
                                          expectedDomains: [Self.first, Self.second])
            try FileManager.default.removeItem(at: Self.journal)
            result.cleaned = true
            write(result); status = recovery ? "QA recovery complete" : "CloudKit live QA complete"
        } catch {
            if var result = receipt {
                result.errorCode = (error as NSError).code
                write(result)
            }
            status = "CloudKit QA stopped — check receipt and journal"
        }
    }
}
#endif
