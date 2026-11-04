import XCTest
@testable import ArvectumProxyLauncherIOSCore

/// No real profiles, network access, Keychain or Device VPN involved.
final class ProfileLibrarySelectionPolicyTests: XCTestCase {
    private func makeFixture() -> ([ProxyProfile], ProfileOrganization) {
        let profiles = [
            ProxyProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                         name: "Alpha", host: "alpha.invalid", port: 8000, type: .http),
            ProxyProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                         name: "Bravo", host: "bravo.invalid", port: 9000, type: .socks5),
            ProxyProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                         name: "Charlie", host: "charlie.invalid", port: 8080, type: .https)
        ]
        var organization = ProfileOrganization()
        organization.toggleFavorite(profiles[1].id)
        organization.assignGroup("Рабочие", to: [profiles[0].id, profiles[2].id])
        organization.assignGroup("Резервные", to: [profiles[1].id])
        return (profiles, organization)
    }

    func testFavoritesFirstWithoutChangingStorageOrder() {
        let (profiles, organization) = makeFixture()
        let result = ProfileLibrarySelectionPolicy.visibleProfiles(
            profiles, search: "", groupFilter: "all", organization: organization
        )
        XCTAssertEqual(result.map(\.name), ["Bravo", "Alpha", "Charlie"])
        XCTAssertEqual(profiles.map(\.name), ["Alpha", "Bravo", "Charlie"])
    }

    func testSearchMatchesCaseInsensitiveNameOrHost() {
        let (profiles, organization) = makeFixture()
        XCTAssertEqual(ProfileLibrarySelectionPolicy.visibleProfiles(
            profiles, search: "bRa", groupFilter: "all", organization: organization
        ).map(\.name), ["Bravo"])
        XCTAssertEqual(ProfileLibrarySelectionPolicy.visibleProfiles(
            profiles, search: "CHARLIE.INVALID", groupFilter: "all", organization: organization
        ).map(\.name), ["Charlie"])
    }

    func testFavoritesGroupAndCombinedSearch() {
        let (profiles, organization) = makeFixture()
        XCTAssertEqual(ProfileLibrarySelectionPolicy.visibleProfiles(
            profiles, search: "", groupFilter: "favorites", organization: organization
        ).map(\.name), ["Bravo"])
        XCTAssertEqual(ProfileLibrarySelectionPolicy.visibleProfiles(
            profiles, search: "", groupFilter: "group:Рабочие", organization: organization
        ).map(\.name), ["Alpha", "Charlie"])
        XCTAssertEqual(ProfileLibrarySelectionPolicy.visibleProfiles(
            profiles, search: "charlie", groupFilter: "group:Рабочие", organization: organization
        ).map(\.name), ["Charlie"])
        XCTAssertTrue(ProfileLibrarySelectionPolicy.visibleProfiles(
            profiles, search: "", groupFilter: "group:", organization: organization
        ).isEmpty)
        XCTAssertTrue(ProfileLibrarySelectionPolicy.visibleProfiles(
            profiles, search: "", groupFilter: "invalid-filter", organization: organization
        ).isEmpty)
    }

    func testSelectionNeverIncludesFilteredOrDeletedProfiles() {
        let (profiles, organization) = makeFixture()
        let allSelected = Set(profiles.map(\.id))
        let favorites = ProfileLibrarySelectionPolicy.visibleProfiles(
            profiles, search: "", groupFilter: "favorites", organization: organization
        )
        XCTAssertEqual(ProfileLibrarySelectionPolicy.selectedVisibleIDs(
            allSelected, from: favorites
        ), [profiles[1].id])
        let noMatches = ProfileLibrarySelectionPolicy.visibleProfiles(
            profiles, search: "not-present", groupFilter: "all", organization: organization
        )
        XCTAssertTrue(ProfileLibrarySelectionPolicy.selectedVisibleIDs(
            allSelected, from: noMatches
        ).isEmpty)
        XCTAssertEqual(ProfileLibrarySelectionPolicy.selectedVisibleIDs(
            allSelected, from: [profiles[0]]
        ), [profiles[0].id])
    }
}
