import XCTest
@testable import Arvectum_Proxy_Launcher

/// Runs inside the signed app process to read the production Keychain access
/// group after an in-place upgrade. No password, hostname or UUID is logged.
final class PhysicalKeychainReadOnlyTests: XCTestCase {
    func testThreeExistingAuthenticatedProfilesCanReadKeychainWithoutMutation() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires existing authenticated profiles on the owner's physical iPhone")
        #else
        let store = try ProfileStore()
        let existing = store.listProfiles()
        XCTAssertEqual(existing.count, 3, "Three profiles must survive upgrade")
        var accessibleCredentials = 0
        for profile in existing {
            // All three physical pre-upgrade profiles have authentication.
            XCTAssertTrue(profile.username?.isEmpty == false,
                          "Authenticated metadata must not disappear")
            let password = try store.password(for: profile.id)
            XCTAssertNotNil(password, "A previously authenticated proxy lost its Keychain record")
            XCTAssertFalse(password?.isEmpty ?? true, "Keychain secret is unexpectedly empty")
            accessibleCredentials += 1
        }
        XCTAssertEqual(accessibleCredentials, 3)
        #endif
    }
}
