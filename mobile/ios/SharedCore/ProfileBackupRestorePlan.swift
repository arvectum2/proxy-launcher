import Foundation

/// Builds the entire additive, quota-checked restoration plan before the
/// first Keychain or UserDefaults mutation. Existing profile IDs and
/// credentials are never reused or overwritten by a backup file.
struct ProfileBackupRestorePlan {
    let entries: [BackupProfile]
    let favorites: Set<UUID>
    let groups: [UUID: String]

    init(payload: ProfileBackupPayload, existing: [ProxyProfile]) throws {
        func fingerprint(_ item: ProxyProfile) -> String {
            "\(item.type.rawValue)|\(item.host.lowercased())|\(item.port)|\(item.username ?? "")"
        }
        var seen = Set(existing.map(fingerprint))
        var restored: [BackupProfile] = []
        var remapped: [UUID: UUID] = [:]
        for item in payload.profiles {
            guard seen.insert(fingerprint(item.profile)).inserted else { continue }
            let original = item.profile
            let replacement = ProxyProfile(name: original.name, host: original.host,
                                           port: original.port, type: original.type,
                                           username: original.username)
            remapped[original.id] = replacement.id
            restored.append(BackupProfile(profile: replacement, password: item.password))
        }
        guard existing.count + restored.count <= ProfileBackupCodec.maxProfiles else {
            throw ProfileBackupError.tooManyProfiles
        }
        entries = restored
        favorites = Set(payload.favorites.compactMap { remapped[$0] })
        groups = Dictionary(uniqueKeysWithValues: payload.groups.compactMap { key, value in
            remapped[key].map { ($0, value) }
        })
    }
}
