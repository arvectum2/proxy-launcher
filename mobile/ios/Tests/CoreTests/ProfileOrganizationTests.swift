import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProfileOrganizationTests: XCTestCase {
    func testDefaultLegacyProfilesDoNotRequireMigration() throws {
        let id = UUID()
        let legacy = ProfileOrganization()
        XCTAssertFalse(legacy.isFavorite(id))
        XCTAssertNil(legacy.group(for: id))
        let restored = try JSONDecoder().decode(ProfileOrganization.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(restored, legacy)
    }

    func testFavoriteGroupAndPruneDoNotAffectOtherEntries() {
        let first = UUID(), second = UUID()
        var value = ProfileOrganization()
        value.toggleFavorite(first)
        value.assignGroup("  Резервные  ", to: [first, second])
        XCTAssertEqual(value.group(for: second), "Резервные")
        XCTAssertTrue(value.isFavorite(first))
        value.prune(keeping: [second])
        XCTAssertFalse(value.isFavorite(first))
        XCTAssertNil(value.group(for: first))
        XCTAssertEqual(value.groupNames, ["Резервные"])
    }

    func testEmptyGroupUnassignsAndTruncatesName() {
        let id = UUID()
        var value = ProfileOrganization()
        value.assignGroup(String(repeating: "g", count: 80), to: [id])
        XCTAssertEqual(value.group(for: id)?.count, 40)
        value.assignGroup("   ", to: [id])
        XCTAssertNil(value.group(for: id))
        value.toggleFavorite(id)
        value.toggleFavorite(id)
        XCTAssertFalse(value.isFavorite(id))
    }
}
