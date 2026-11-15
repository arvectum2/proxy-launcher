import Foundation

/// Separate explicit encrypted native backup. No automatic export, sync or
/// Keychain access. Only current records supplied by the caller, no tickets,
/// active selection, session state, retired records or legacy proxy secrets.
enum NativeProfileBackupCodec {
    private static let magic = "arvectum.apl.encrypted-native-profiles"
    static let maxProfiles = 32
    private struct Item: Codable {
        let reference: NativeCredentialRecord.Reference
        let record: Data
    }
    private struct Payload: Codable { let version: Int; let records: [Item] }
    static func seal(_ records: [NativeCredentialRecord], password: String) throws -> Data {
        try validate(records)
        let items = try records.map { Item(reference:$0.reference,record:try $0.encoded()) }
        return try ProfileBackupCodec.sealPayloadBytes(JSONEncoder().encode(Payload(version:1,records:items)),password:password,format:magic)
    }
    static func open(_ data: Data,password: String) throws -> [NativeCredentialRecord] {
        let bytes = try ProfileBackupCodec.openPayloadBytes(data,password:password,format:magic)
        guard let payload = try? JSONDecoder().decode(Payload.self,from:bytes), payload.version == 1,
              (1...maxProfiles).contains(payload.records.count) else {throw ProfileBackupError.invalidFile}
        let records = try payload.records.map { try NativeCredentialRecord.decode($0.record,expected:$0.reference) }
        try validate(records)
        return records
    }
    private static func validate(_ records: [NativeCredentialRecord]) throws {
        guard (1...maxProfiles).contains(records.count) else {throw ProfileBackupError.tooManyProfiles}
        guard Set(records.map(\.reference.profileID)).count == records.count else {throw ProfileBackupError.invalidFile}
    }
    /// Pure additive plan. A future writer must separately journal the entire
    /// import and enforce VPN-OFF plus catalog capacity at commit time.
    /// Never reuses a saved ID/revision or changes the current selection.
    static func prepareRestore(_ records: [NativeCredentialRecord], existingNativeIDs: Set<UUID>, legacyIDs: Set<UUID>) throws -> [NativeCredentialRecord] {
        try validate(records)
        guard existingNativeIDs.count <= maxProfiles-records.count else {throw ProfileBackupError.tooManyProfiles}
        var reserved=existingNativeIDs.union(legacyIDs).union(records.map(\.reference.profileID))
        return try records.map { old in
            let id=UUID()
            guard reserved.insert(id).inserted else {throw ProfileBackupError.invalidFile}
            return try old.copyForRestore(profileID:id)
        }
    }
}
