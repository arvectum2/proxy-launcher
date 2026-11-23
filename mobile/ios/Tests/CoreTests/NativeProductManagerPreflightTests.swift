import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeProductManagerPreflightTests: XCTestCase {
    typealias Gate = NativeProductManagerPreflight

    func testReadbackPermitsOnlySingleOwnedInvalidProductManager() {
        XCTAssertTrue(Gate.permitsReadback([.disconnected, .invalid], ownedProductIndex:1))
        XCTAssertTrue(Gate.permitsReadback([.disconnected], ownedProductIndex:nil))
        XCTAssertFalse(Gate.permitsReadback([.disconnected, .invalid], ownedProductIndex:nil))
        XCTAssertFalse(Gate.permitsReadback([.invalid, .disconnected], ownedProductIndex:1))
        XCTAssertFalse(Gate.permitsReadback([.invalid, .invalid], ownedProductIndex:1))
        XCTAssertFalse(Gate.permitsReadback([.activeOrUnknown], ownedProductIndex:0))
        XCTAssertFalse(Gate.permitsReadback([.disconnected, .activeOrUnknown], ownedProductIndex:1))
    }

    func testStartPhaseVocabularyDoesNotContainIdentityOrNetworkValues() {
        XCTAssertEqual(NativeProductStartPhase.allCases.map(\.rawValue), [
            "manager-census", "manager-reconcile", "manager-readback",
            "credential-ticket", "os-submission"
        ])
    }

    func testRejectedSystemSubmissionRevokesTicketAndPreservesCause() {
        enum Failure: Error, Equatable { case networkExtension, keychain }
        var attempts = 0, revocations = 0
        XCTAssertThrowsError(try NativeProductStartSubmission.attempt({
            attempts += 1
            throw Failure.networkExtension
        },revoke:{
            revocations += 1
            throw Failure.keychain
        })) { error in
            XCTAssertEqual(error as? Failure, .networkExtension)
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(revocations, 1)
    }

    func testAcceptedSystemSubmissionDoesNotRevokeTicket() throws {
        var attempts = 0, revocations = 0
        try NativeProductStartSubmission.attempt({
            attempts += 1
        },revoke:{
            revocations += 1
        })
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(revocations, 0)
    }

    func testLaunchNeverAcceptsInvalidOrActiveManager() {
        XCTAssertTrue(Gate.permitsLaunch([]))
        XCTAssertTrue(Gate.permitsLaunch([.disconnected,.disconnected]))
        XCTAssertFalse(Gate.permitsLaunch([.invalid]))
        XCTAssertFalse(Gate.permitsLaunch([.disconnected,.invalid]))
        XCTAssertFalse(Gate.permitsLaunch([.activeOrUnknown]))
    }
}
