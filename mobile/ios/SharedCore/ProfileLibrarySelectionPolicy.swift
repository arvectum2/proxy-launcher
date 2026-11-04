import Foundation

/// Deterministic, side-effect-free library filtering. In particular,
/// deletion and bulk operations may act only on selected *visible* profiles.
enum ProfileLibrarySelectionPolicy {
    static func visibleProfiles(
        _ profiles: [ProxyProfile],
        search: String,
        groupFilter: String,
        organization: ProfileOrganization
    ) -> [ProxyProfile] {
        profiles.filter { profile in
            let matchesSearch = search.isEmpty ||
                profile.name.localizedCaseInsensitiveContains(search) ||
                profile.host.localizedCaseInsensitiveContains(search)
            let matchesGroup: Bool
            switch groupFilter {
            case "all": matchesGroup = true
            case "favorites": matchesGroup = organization.isFavorite(profile.id)
            default:
                matchesGroup = groupFilter.hasPrefix("group:") &&
                    organization.group(for: profile.id) == String(groupFilter.dropFirst(6))
            }
            return matchesSearch && matchesGroup
        }.sorted { lhs, rhs in
            let leftFavorite = organization.isFavorite(lhs.id)
            let rightFavorite = organization.isFavorite(rhs.id)
            if leftFavorite != rightFavorite { return leftFavorite }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func selectedVisibleIDs(
        _ selection: Set<UUID>, from profiles: [ProxyProfile]
    ) -> Set<UUID> {
        selection.intersection(Set(profiles.map(\.id)))
    }
}
