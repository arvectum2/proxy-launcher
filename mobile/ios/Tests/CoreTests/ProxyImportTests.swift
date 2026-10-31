import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProxyImportTests: XCTestCase {
    func testImportWithCredentialsAndLabel() throws {
        let item = try XCTUnwrap(ProxyImport.parse("socks5://alice:p%40ss@proxy.example:1080#Work").first)
        XCTAssertEqual(item.type, .socks5)
        XCTAssertEqual(item.username, "alice")
        XCTAssertEqual(item.password, "p@ss")
        XCTAssertEqual(item.name, "Work")
    }
    func testMultipleLinesAndComments() throws {
        let items = try ProxyImport.parse("# list\nhttp://one.example:8080\nhttps://two.example:443")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[1].type, .https)
    }
    func testRejectsInvalidAndUnsupported() {
        for value in ["vless://a@b:443", "http://host", "http://host:0", "http://host:99999", "http://host:80/path"] {
            XCTAssertThrowsError(try ProxyImport.parse(value), value)
        }
    }
    func testRejectsOversizedInput() {
        XCTAssertThrowsError(try ProxyImport.parse(String(repeating: "a", count: 256_001)))
    }
}
