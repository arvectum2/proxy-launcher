import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ApplicationExclusionCapabilityTests: XCTestCase {
    func testConsumerPacketTunnelDoesNotClaimPerAppEnforcement() {
        let capability = IOSApplicationExclusionCapability(mode: .consumerPacketTunnel)
        XCTAssertFalse(capability.canSelectInstalledApplications)
        XCTAssertFalse(capability.canEnforcePerApplicationRouting)
        XCTAssertTrue(capability.requiresDeviceManagement)
    }

    func testManagedPerAppVPNReportsEnforcementCapability() {
        let capability = IOSApplicationExclusionCapability(mode: .managedPerAppVPN)
        XCTAssertTrue(capability.canSelectInstalledApplications)
        XCTAssertTrue(capability.canEnforcePerApplicationRouting)
        XCTAssertTrue(capability.requiresDeviceManagement)
    }
}
