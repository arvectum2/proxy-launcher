import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProxyImportFileReaderTests: XCTestCase {
    private func withTempFile(_ bytes: Data, _ test: (URL) throws -> Void) throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("apl-bounded-file-test-\(UUID().uuidString).txt")
        try bytes.write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }
        try test(file)
    }

    func testShortUTF8AndUnicodeCredentialsRoundTrip() throws {
        let source = "socks5://用户:p%40ss@proxy.example:1080#Тест💜"
        try withTempFile(Data(source.utf8)) { file in
            XCTAssertEqual(try ProxyImportFileReader.readUTF8(from: file), source)
            let profile = try XCTUnwrap(ProxyImport.parse(ProxyImportFileReader.readUTF8(from: file)).first)
            XCTAssertEqual(profile.username, "用户")
            XCTAssertEqual(profile.password, "p@ss")
        }
    }

    func testEmptyFileReturnsEmptyTextAndParserStillRejects() throws {
        try withTempFile(Data()) { file in
            let source = try ProxyImportFileReader.readUTF8(from: file)
            XCTAssertTrue(source.isEmpty)
            XCTAssertThrowsError(try ProxyImport.parse(source))
        }
    }

    func testExactly256000BytesAllowedAndOneOverRejected() throws {
        let exact = Data(repeating: 0x61, count: 256_000)
        try withTempFile(exact) { file in
            XCTAssertEqual(try ProxyImportFileReader.readUTF8(from: file).utf8.count, 256_000)
        }
        let oversize = Data(repeating: 0x61, count: 256_001)
        try withTempFile(oversize) { file in
            XCTAssertThrowsError(try ProxyImportFileReader.readUTF8(from: file)) { error in
                guard case ProxyImportError.tooLarge = error else {
                    XCTFail("Expected size limit, got \(type(of: error))")
                    return
                }
            }
        }
    }

    func testMultiMegabyteFileRejectedBeforeFullRead() throws {
        // The source uses fixed 16KiB reads with a +1 byte limit check.
        try withTempFile(Data(repeating: 0x78, count: 4 * 1024 * 1024)) { file in
            XCTAssertThrowsError(try ProxyImportFileReader.readUTF8(from: file)) { error in
                guard case ProxyImportError.tooLarge = error else {
                    XCTFail("Wrong error category: \(type(of: error))")
                    return
                }
            }
        }
    }

    func testInvalidUTF8DoesNotReturnReplacedOrPartialCredentials() throws {
        try withTempFile(Data([0x68, 0x6f, 0x73, 0x74, 0xff])) { file in
            XCTAssertThrowsError(try ProxyImportFileReader.readUTF8(from: file)) { error in
                guard case ProxyImportError.invalid = error else {
                    XCTFail("Unexpected error category")
                    return
                }
            }
        }
    }

    func testNonFileURLRejectedAndNoNetworkFetch() {
        XCTAssertThrowsError(try ProxyImportFileReader.readUTF8(from:
            URL(string: "https://supplier.example.invalid/proxies.txt")!))
    }
}
