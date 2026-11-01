import Foundation

/// Optional, non-secret UI organization metadata, kept separately from
/// profiles.v1 so upgrades preserve proxy configurations and Keychain entries.
struct ProfileOrganization: Codable, Equatable {
    private(set) var favorites: Set<UUID> = []
    private(set) var groups: [UUID: String] = [:]

    func isFavorite(_ id: UUID) -> Bool { favorites.contains(id) }
    func group(for id: UUID) -> String? { groups[id] }

    var groupNames: [String] {
        Array(Set(groups.values)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    mutating func toggleFavorite(_ id: UUID) {
        if !favorites.insert(id).inserted { favorites.remove(id) }
    }

    /// Bulk favorites are idempotent: repeating the action never toggles
    /// profiles into the opposite state by accident.
    mutating func setFavorite(_ enabled: Bool, for ids: Set<UUID>) {
        if enabled { favorites.formUnion(ids) }
        else { favorites.subtract(ids) }
    }

    mutating func assignGroup(_ group: String?, to ids: Set<UUID>) {
        let cleaned = group?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = String(cleaned.prefix(40))
        for id in ids {
            if name.isEmpty { groups.removeValue(forKey: id) }
            else { groups[id] = name }
        }
    }

    mutating func prune(keeping ids: Set<UUID>) {
        favorites.formIntersection(ids)
        groups = groups.filter { ids.contains($0.key) }
    }
}
