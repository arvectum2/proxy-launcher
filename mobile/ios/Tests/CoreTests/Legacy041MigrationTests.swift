import XCTest
@testable import ArvectumProxyLauncherIOSCore

/// 0.1.41 (46) serialized ProxyProfile layout, before 0.2.0 groups/backup.
/// The fixture contains no real proxy, password or production account.
final class Legacy041MigrationTests: XCTestCase {
    func testLegacyProfileJSONDecodesAndReencodesUnchanged() throws {
        let legacy = """
        [
          {"id":"11111111-2222-4333-8444-555555555555","name":"Legacy QA",
           "host":"legacy.qa-example.invalid","port":8000,"type":"HTTP",
           "username":"legacy-synthetic"},
          {"id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","name":"Backup QA",
           "host":"backup.qa-example.invalid","port":8080,"type":"SOCKS5",
           "username":null}
        ]
        """
        let profiles = try JSONDecoder().decode([ProxyProfile].self, from: Data(legacy.utf8))
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0].id.uuidString, "11111111-2222-4333-8444-555555555555".uppercased())
        XCTAssertEqual(profiles[0].host, "legacy.qa-example.invalid")
        XCTAssertEqual(profiles[0].port, 8000)
        XCTAssertEqual(profiles[0].username, "legacy-synthetic")
        XCTAssertEqual(profiles[0].type, .http)
        XCTAssertEqual(profiles[1].type, .socks5)
        XCTAssertNil(profiles[1].username)
        let reloaded = try JSONDecoder().decode([ProxyProfile].self,
                                                from: JSONEncoder().encode(profiles))
        XCTAssertEqual(reloaded, profiles)
    }

    func testNewProfileGroupsDefaultToEmptyForLegacyProfiles() {
        let a = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let b = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        let organization = ProfileOrganization()
        XCTAssertNil(organization.group(for: a))
        XCTAssertFalse(organization.isFavorite(a))
        XCTAssertNil(organization.group(for: b))
    }
}
