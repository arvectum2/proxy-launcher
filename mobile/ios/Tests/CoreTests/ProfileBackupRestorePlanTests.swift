import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProfileBackupRestorePlanTests: XCTestCase {
    func testExistingProfilesAndAccountsAreNotOverwritten() throws {
        let existing = ProxyProfile(name: "My active server", host: "PROXY.EXAMPLE", port: 8080,
                                    type: .http, username: "account")
        let fresh = ProxyProfile(name: "New", host: "fresh.example", port: 1080, type: .socks5)
        let copy = ProxyProfile(name: "Duplicate", host: "proxy.example", port: 8080,
                                type: .http, username: "account")
        let payload = ProfileBackupPayload(profiles: [BackupProfile(profile: copy, password: "replacement"),
                                                      BackupProfile(profile: fresh, password: "local")],
                                           favorites: [copy.id, fresh.id],
                                           groups: [copy.id: "Old", fresh.id: "New"])
        let plan = try ProfileBackupRestorePlan(payload: payload, existing: [existing])
        XCTAssertEqual(plan.entries.count, 1)
        XCTAssertEqual(plan.entries[0].profile.host, fresh.host)
        XCTAssertNotEqual(plan.entries[0].profile.id, fresh.id)
        XCTAssertEqual(plan.favorites, [plan.entries[0].profile.id])
        XCTAssertEqual(plan.groups, [plan.entries[0].profile.id: "New"])
    }

    func testQuotaFailureIsAtomicAtPlanningStage() throws {
        let existing = (0..<200).map { index in
            ProxyProfile(name: "Existing", host: "host\(index).example", port: 8080, type: .http)
        }
        let additional = ProxyProfile(name: "New", host: "new.example", port: 8080, type: .http)
        let payload = ProfileBackupPayload(profiles: [BackupProfile(profile: additional, password: nil)],
                                           favorites: [], groups: [:])
        XCTAssertThrowsError(try ProfileBackupRestorePlan(payload: payload, existing: existing))
    }
}
