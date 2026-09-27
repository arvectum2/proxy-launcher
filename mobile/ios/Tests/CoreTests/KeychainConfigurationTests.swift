import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class KeychainConfigurationTests: XCTestCase {
    func testCredentialAccessGroupMatchesSigningTeam() {
        XCTAssertEqual(IOSKeychainConfiguration.teamIdentifier, "VML75VY94V")
        XCTAssertEqual(
            IOSKeychainConfiguration.credentialAccessGroup,
            "VML75VY94V.ru.arvectum.proxylauncher.ios.shared"
        )
    }

    func testCredentialAccessGroupIsFullyResolvedAtRuntime() {
        XCTAssertFalse(IOSKeychainConfiguration.credentialAccessGroup.contains("$("))
        XCTAssertTrue(
            IOSKeychainConfiguration.credentialAccessGroup
                .hasPrefix(IOSKeychainConfiguration.teamIdentifier + ".")
        )
    }
}
