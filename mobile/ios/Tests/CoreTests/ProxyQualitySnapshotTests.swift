import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProxyQualitySnapshotTests: XCTestCase {
    func testFreshMeasurementsRoundTripAndExpire() throws {
        let good = UUID(), stale = UUID(), unknown = UUID()
        let now = Date()
        var snapshot = ProxyQualitySnapshot()
        snapshot.markAvailable(good, latencyMs: 55, at: now)
        snapshot.markAvailable(stale, latencyMs: 25, at: now.addingTimeInterval(-700))
        snapshot.markAvailable(unknown, latencyMs: 1, at: now)
        let restored = try JSONDecoder().decode(ProxyQualitySnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.freshLatencies(for: [good, stale], at: now), [good: 55])
    }

    func testFailuresAndRemovedProfilesDoNotAppearInRanking() {
        let a = UUID(), b = UUID()
        var value = ProxyQualitySnapshot()
        value.markAvailable(a, latencyMs: 90)
        value.markAvailable(b, latencyMs: 120)
        value.markUnavailable(a)
        value.prune(keeping: [a])
        XCTAssertTrue(value.freshLatencies(for: [a, b]).isEmpty)
        value.markAvailable(a, latencyMs: 0)
        XCTAssertTrue(value.freshLatencies(for: [a]).isEmpty)
    }
}
