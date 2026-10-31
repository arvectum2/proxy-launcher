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

extension ProxyImportTests {
    func testDeepLink() throws {
        let url = URL(string: "arvectum-proxy://import?data=http%3A%2F%2Fproxy.example%3A8080")!
        XCTAssertEqual(try ProxyImport.fromDeepLink(url), "http://proxy.example:8080")
        XCTAssertThrowsError(try ProxyImport.fromDeepLink(URL(string: "arvectum-proxy://other?data=x")!))
    }
    func testDuplicateFiltering() throws {
        let items = try ProxyImport.parse("http://EXAMPLE.com:8080\nhttp://example.com:8080\nsocks5://example.com:8080")
        let existing = [ProxyProfile(name: "Saved", host: "example.com", port: 8080, type: .http)]
        XCTAssertEqual(ProxyImport.withoutDuplicates(items, existing: existing).count, 1)
    }
}

extension ProxyImportTests {
    func testSupplierRawIPPortUserPasswordAndTypeSelection() throws {
        let items = try ProxyImport.parse("# provider\n192.0.2.10:8080:alice:secret:with:colons\n198.51.100.20:1080:bob:p@ss",
                                          defaultType: .socks5)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].host, "192.0.2.10")
        XCTAssertEqual(items[0].port, 8080)
        XCTAssertEqual(items[0].type, .socks5)
        XCTAssertEqual(items[0].username, "alice")
        XCTAssertEqual(items[0].password, "secret:with:colons")
        XCTAssertEqual(items[1].username, "bob")
        XCTAssertEqual(items[1].password, "p@ss")
    }

    func testSupplierHostPortDefaultsToHTTPAndSupportsIPv6() throws {
        let items = try ProxyImport.parse("proxy.example:3128\n[2001:db8::5]:1080:user:password")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].type, .http)
        XCTAssertEqual(items[1].host, "[2001:db8::5]")
        XCTAssertEqual(items[1].port, 1080)
    }

    func testMixRawAndURLPreservesExplicitProtocol() throws {
        let items = try ProxyImport.parse("proxy.example:3128:u:p\nsocks5://x:y@proxy.example:1080",
                                          defaultType: .https)
        XCTAssertEqual(items.map(\.type), [.https, .socks5])
    }

    func testCSVHeaderOrderAndQuotedCommas() throws {
        let text = "password,IP,protocol,login,port,name\n\"pass,word\",192.0.2.42,SOCKS5,alice,1080,Work\r\n"
        let item = try XCTUnwrap(ProxyImport.parse(text).first)
        XCTAssertEqual(item.host, "192.0.2.42")
        XCTAssertEqual(item.port, 1080)
        XCTAssertEqual(item.name, "Work")
        XCTAssertEqual(item.type, .socks5)
        XCTAssertEqual(item.username, "alice")
        XCTAssertEqual(item.password, "pass,word")
    }

    func testCSVSemicolonRussianHeadersAndDefaultProtocol() throws {
        let items = try ProxyImport.parse("Адрес;Порт;Логин;Пароль\nproxy.example;443;user;секрет", defaultType: .https)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .https)
        XCTAssertEqual(items[0].password, "секрет")
    }

    func testCSVHeaderlessAndTabDelimited() throws {
        let rows = try ProxyImport.parse("192.0.2.1,8080,user,pass\n192.0.2.2,1080,a,b")
        XCTAssertEqual(rows.count, 2)
        let tab = try ProxyImport.parse("host\tport\tusername\tpassword\nproxy.example\t8080\tu\tp")
        XCTAssertEqual(tab.first?.username, "u")
    }

    func testXMLAttributesAndChildElements() throws {
        let xml = """
        <?xml version="1.0"?>
        <proxies>
          <proxy host="192.0.2.3" port="8080" username="alice" password="abc" type="http" name="Office" />
          <proxy><ip>proxy.example</ip><port>1080</port><login>bob</login><password>p@ss</password><protocol>socks5</protocol></proxy>
        </proxies>
        """
        let items = try ProxyImport.parse(xml)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "Office")
        XCTAssertEqual(items[1].host, "proxy.example")
        XCTAssertEqual(items[1].type, .socks5)
        XCTAssertEqual(items[1].password, "p@ss")
    }

    func testXMLRejectsExternalEntitiesAndMalformed() {
        let xml = "<!DOCTYPE proxies [<!ENTITY xxe SYSTEM \"file:///etc/passwd\">]><proxies><proxy host=\"&xxe;\" port=\"80\"/></proxies>"
        XCTAssertThrowsError(try ProxyImport.parse(xml))
        XCTAssertThrowsError(try ProxyImport.parse("<proxies><proxy host=\"a\" port=\"80\"></proxies>"))
    }

    func testNoPartialImportForBadRecordAcrossAllFormats() {
        let samples = [
            "192.0.2.1:8080:u:p\n192.0.2.2:99999:x:y",
            "host,port,username,password\n192.0.2.1,8080,u,p\n192.0.2.2,99999,a,b",
            "<proxies><proxy host=\"192.0.2.1\" port=\"8080\"/><proxy host=\"192.0.2.2\" port=\"99999\"/></proxies>",
            "host,port\nproxy.example,8080\n\"broken,9000",
        ]
        for sample in samples { XCTAssertThrowsError(try ProxyImport.parse(sample)) }
    }

    func testCSVQuotedPasswordWithNewlineAndEscapedQuote() throws {
        let text = "host,port,user,pass\nproxy.example,8080,a,\"a\"\"b\nc\""
        let item = try XCTUnwrap(ProxyImport.parse(text).first)
        XCTAssertEqual(item.password, "a\"b\nc")
    }

    func testBatchLimitAndRawInvalids() {
        let huge = Array(repeating: "proxy.example:8080:u:p", count: 201).joined(separator: "\n")
        XCTAssertThrowsError(try ProxyImport.parse(huge))
        for entry in ["proxy.example:notaport:u:p", "proxy.example:70000:u:p", "proxy.example:8080:u", "http://bad:80/path", "malformed::u:p"] {
            XCTAssertThrowsError(try ProxyImport.parse(entry), entry)
        }
    }
}
