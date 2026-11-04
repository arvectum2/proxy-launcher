import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProxyImportJSONTests: XCTestCase {
    func testJSONProviderListAndUnicodeCredentials() throws {
        let input = """
        {"proxies":[
          {"host":"proxy.example","port":1080,"login":"用户","password":"секрет:💜","protocol":"socks5","label":"家"},
          {"ip":"192.0.2.5","port":"443","type":"https","user":"alice","pass":"p@ss"},
          "http://bob:p%40ss@web.example:8080"
        ]}
        """
        let rows = try ProxyImport.parse(input)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].host, "proxy.example")
        XCTAssertEqual(rows[0].port, 1080)
        XCTAssertEqual(rows[0].type, .socks5)
        XCTAssertEqual(rows[0].username, "用户")
        XCTAssertEqual(rows[0].password, "секрет:💜")
        XCTAssertEqual(rows[0].name, "家")
        XCTAssertEqual(rows[1].type, .https)
        XCTAssertEqual(rows[1].password, "p@ss")
        XCTAssertEqual(rows[2].password, "p@ss")
    }

    func testTopLevelObjectAndArrayPreserveDefaultType() throws {
        let single = try XCTUnwrap(ProxyImport.parse(#"{"server":"proxy.example","port":8080}"#, defaultType: .socks5).first)
        XCTAssertEqual(single.type, .socks5)
        let list = try ProxyImport.parse(#"[{"host":"proxy.example","port":80},{"host":"next.example","port":"443","protocol":"https"}]"#)
        XCTAssertEqual(list.map(\.type), [.http, .https])
    }

    func testIPv6LegacyAndJSONHostCannotBeConfused() throws {
        let raw = try XCTUnwrap(ProxyImport.parse("[2001:db8::5]:1080:user:pass").first)
        XCTAssertEqual(raw.host, "[2001:db8::5]")
        let json = try XCTUnwrap(ProxyImport.parse(#"[{"host":"2001:db8::5","port":1080,"type":"socks5"}]"#).first)
        XCTAssertEqual(json.host, "[2001:db8::5]")
        XCTAssertEqual(json.port, 1080)
    }

    func testMalformedRecordsRejectWholeBatch() {
        let invalid = [
            #"{"proxies":[{"host":"valid.example","port":80},{"host":"invalid.example","port":99999}]}"#,
            #"{"proxies":[{"host":"valid.example","port":80},null]}"#,
            #"{"proxies":[{"host":"valid.example","port":80}, {"host":"x.example","port":false}]}"#,
            #"{"proxies":[{"host":"valid.example","port":80}, {"host":"x.example","port":1.5}]}"#,
            #"{"proxies":[{"host":"valid.example","port":80}, {"host":"x.example","port":"abc"}]}"#,
            #"{"proxies":[{"host":"valid.example","port":80},{"host":"x.example","port":80,"password":true}]}"#,
            #"{"proxies":[{"host":"valid.example","port":80},{"host":"x.example","port":80,"username":["nested"]}]}"#,
            #"{"proxies":[{"host":"valid.example","port":80},{"host":"x.example","port":80,"type":"vless"}]}"#,
            #"{"proxies":[{"host":"valid.example","port":80}],"extra":"ambiguous"}"#,
            #"{"host":"a.example","ip":"b.example","port":80}"#,
            #"{"host":"valid.example","port":80,"unexpected":{"nested":"value"}}"#,
            #"{"host":"valid.example","port":80"#,
            #"{"proxies":{"host":"valid.example","port":80}}"#,
            #"{"host":"valid.example","port":null}"#,
            #"{"host":true,"port":80}"#,
            #"["http://valid.example:80","not-a-proxy"]"#,
            #"["http://valid.example:80","http://bad.example:80\nanother.example:80"]"#
        ]
        for sample in invalid {
            XCTAssertThrowsError(try ProxyImport.parse(sample), sample.prefix(50).description)
        }
    }

    func testEmptyAndBoundedListAndInputSize() throws {
        XCTAssertThrowsError(try ProxyImport.parse("[]"))
        XCTAssertThrowsError(try ProxyImport.parse(#"{"proxies":[]}"#))
        let valid = Array(repeating: #"{"host":"proxy.example","port":8080}"#, count: 200).joined(separator: ",")
        XCTAssertEqual(try ProxyImport.parse("[\(valid)]").count, 200)
        XCTAssertThrowsError(try ProxyImport.parse("[\(valid),\(valid)]"))
        XCTAssertThrowsError(try ProxyImport.parse("[\(String(repeating: " ", count: 256_001))]"))
    }

    func testOldFormatsRemainAvailable() throws {
        XCTAssertEqual(try ProxyImport.parse("192.0.2.1:8080:user:secret").count, 1)
        XCTAssertEqual(try ProxyImport.parse("host,port\nproxy.example,443").count, 1)
        XCTAssertEqual(try ProxyImport.parse(#"<proxies><proxy host="proxy.example" port="8080"/></proxies>"#).count, 1)
        XCTAssertEqual(try ProxyImport.parse("https://proxy.example:443").count, 1)
    }
}
