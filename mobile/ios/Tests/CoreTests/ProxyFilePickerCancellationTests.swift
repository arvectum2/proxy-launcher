import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProxyFilePickerCancellationTests: XCTestCase {
    func testCocoaUserCancellationIsSilent() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
                            userInfo: [NSLocalizedDescriptionKey: "Potentially sensitive path"])
        XCTAssertTrue(ProxyFilePickerCancellation.isUserCancellation(error))
    }

    func testTypedCocoaCancellationIsSilent() {
        XCTAssertTrue(ProxyFilePickerCancellation.isUserCancellation(CocoaError(.userCancelled)))
    }

    func testIdenticalCodeFromOtherDomainIsNotSilenced() {
        let external = NSError(domain: NSURLErrorDomain, code: NSUserCancelledError)
        XCTAssertFalse(ProxyFilePickerCancellation.isUserCancellation(external))
        let custom = NSError(domain: "com.example.untrusted", code: NSUserCancelledError)
        XCTAssertFalse(ProxyFilePickerCancellation.isUserCancellation(custom))
    }

    func testOtherCocoaFilesystemErrorsAreNotSilenced() {
        let missing = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        XCTAssertFalse(ProxyFilePickerCancellation.isUserCancellation(missing))
        let inaccessible = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        XCTAssertFalse(ProxyFilePickerCancellation.isUserCancellation(inaccessible))
    }

    func testUnrelatedSwiftErrorsAreNotSilenced() {
        XCTAssertFalse(ProxyFilePickerCancellation.isUserCancellation(ProxyImportError.invalid))
        XCTAssertFalse(ProxyFilePickerCancellation.isUserCancellation(ProxyImportError.tooLarge))
    }
}
