import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class XrayVLESSRuntimeConfigTests: XCTestCase {
    private let key = Data(repeating: 17, count: 32)
    private var keyText: String {
        key.base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
    private let id = "12345678-abcd-abcd-abcd-123456789abc"

    private func candidate(flow: Bool = true) throws -> VLESSRealityShareLink {
        try VLESSRealityShareLink.parse(
            "vless://\(id)@example.com:443?encryption=none&security=reality&type=tcp" +
            "&sni=example.com&fp=chrome&pbk=\(keyText)&sid=abcd" +
            (flow ? "&flow=xtls-rprx-vision" : "") + "#Synthetic")
    }

    private func converted(flow: Bool = true) -> [String: Any] {
        var settings: [String: Any] = [
            "address": "example.com", "port": 443, "id": id, "encryption": "none"
        ]
        if flow { settings["flow"] = "xtls-rprx-vision" }
        return [
            "protocol": "vless", "tag": "Synthetic", "settings": settings,
            "streamSettings": [
                "network": "tcp", "security": "reality",
                "realitySettings": [
                    "fingerprint": "chrome", "password": keyText,
                    "serverName": "example.com", "shortId": "abcd"
                ]
            ]
        ]
    }

    private func response(_ outbounds: [[String: Any]],
                          extras: [String: Any] = [:]) throws -> Data {
        var data: [String: Any] = ["outbounds": outbounds]
        for (key, value) in extras { data[key] = value }
        return try JSONSerialization.data(withJSONObject: [
            "success": true, "data": data, "error": ""
        ])
    }

    func testOnlyLoopbackSocksAndVerifiedVLESSOutbound() throws {
        let bytes = try XrayVLESSRuntimeConfig.prepare(
            candidate: candidate(), converterResponse: response([converted()]), socksPort: 39879)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let inbounds = try XCTUnwrap(root["inbounds"] as? [[String: Any]])
        XCTAssertEqual(inbounds.count, 1)
        XCTAssertEqual(inbounds[0]["listen"] as? String, "127.0.0.1")
        XCTAssertEqual(inbounds[0]["port"] as? Int, 39879)
        XCTAssertEqual((inbounds[0]["settings"] as? [String: Any])?["udp"] as? Bool, false)
        let outbounds = try XCTUnwrap(root["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds.count, 1)
        XCTAssertEqual(outbounds[0]["protocol"] as? String, "vless")
        XCTAssertEqual(outbounds[0]["tag"] as? String, "apl-vless")
        let settings = try XCTUnwrap(outbounds[0]["settings"] as? [String: Any])
        XCTAssertEqual(settings["id"] as? String, id)
        XCTAssertEqual(settings["flow"] as? String, "xtls-rprx-vision")
        let stream = try XCTUnwrap(outbounds[0]["streamSettings"] as? [String: Any])
        XCTAssertEqual(stream["network"] as? String, "raw")
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("Synthetic"))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("freedom"))
    }

    func testDirectCompilerMatchesVerifiedConverterReconstruction() throws {
        for flow in [true,false] {
            let p=try candidate(flow:flow)
            XCTAssertEqual(try XrayVLESSRuntimeConfig.compileValidatedCandidate(p,socksPort:39879),try XrayVLESSRuntimeConfig.prepare(candidate:p,converterResponse:response([converted(flow:flow)]),socksPort:39879))
            XCTAssertFalse(String(reflecting:p).contains(id));XCTAssertEqual(Mirror(reflecting:p).children.count,0)
        }
    }
    func testNoVisionLinkDoesNotInventFlow() throws {
        let data = try XrayVLESSRuntimeConfig.prepare(
            candidate: candidate(flow: false), converterResponse: response([converted(flow: false)]),
            socksPort: 39879)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("xtls-rprx-vision"))
    }

    func testConverterSuppliedFallbackAndRoutingRejected() throws {
        let profile = try candidate()
        for output in [
            try response([converted(), ["protocol": "freedom"]]),
            try response([converted()], extras: ["routing": ["rules": []]]),
            try response([converted()], extras: ["inbounds": []]),
            try response([])
        ] {
            XCTAssertThrowsError(try XrayVLESSRuntimeConfig.prepare(
                candidate: profile, converterResponse: output, socksPort: 39879))
        }
    }

    func testEndpointIdentityAndTransportCannotChange() throws {
        let profile = try candidate()
        for (field, value): (String, Any) in [
            ("address", "different.example"), ("port", 444), ("id", UUID().uuidString),
            ("encryption", "other"), ("flow", ""), ("unknownSetting", true)
        ] {
            var output = converted()
            var settings = try XCTUnwrap(output["settings"] as? [String: Any])
            settings[field] = value; output["settings"] = settings
            XCTAssertThrowsError(try XrayVLESSRuntimeConfig.prepare(
                candidate: profile, converterResponse: response([output]), socksPort: 39879))
        }
        for (field, value): (String, Any) in [("password", "changed"), ("serverName", "different.example"),
                                              ("fingerprint", "ios"), ("shortId", "bbbb"), ("allowInsecure", true)] {
            var output = converted()
            var stream = try XCTUnwrap(output["streamSettings"] as? [String: Any])
            var reality = try XCTUnwrap(stream["realitySettings"] as? [String: Any])
            reality[field] = value; stream["realitySettings"] = reality; output["streamSettings"] = stream
            XCTAssertThrowsError(try XrayVLESSRuntimeConfig.prepare(
                candidate: profile, converterResponse: response([output]), socksPort: 39879))
        }
    }

    func testPhysicalUnderlayBindingKeepsValidatedRealityCredentials() throws {
        let plain = try XrayVLESSRuntimeConfig.compileValidatedCandidate(
            candidate(), socksPort: 39879, datagramReview: true)
        let pinned = try XrayVLESSRuntimeConfig.bindPhysicalUnderlay(
            plain, interfaceName: "en0", expectedAddress: "example.com", expectedPort: 443)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: pinned) as? [String: Any])
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        let out = try XCTUnwrap((raw["outbounds"] as? [[String: Any]])?.first)
        let before = try XCTUnwrap((original["outbounds"] as? [[String: Any]])?.first)
        let stream = try XCTUnwrap(out["streamSettings"] as? [String: Any])
        let originalStream = try XCTUnwrap(before["streamSettings"] as? [String: Any])
        XCTAssertEqual((stream["sockopt"] as? [String: String])?["interface"], "en0")
        XCTAssertEqual(stream["realitySettings"] as? [String: String],
                       originalStream["realitySettings"] as? [String: String])
        XCTAssertEqual(out["settings"] as? [String: String], before["settings"] as? [String: String])
        XCTAssertEqual((out["settings"] as? [String: Any])?["id"] as? String, id)
        XCTAssertNotNil(raw["inbounds"])
        XCTAssertNotNil(raw["routing"])
        let cellular = try XrayVLESSRuntimeConfig.bindPhysicalUnderlay(
            plain, interfaceName: "pdp_ip0", expectedAddress: "example.com", expectedPort: 443)
        XCTAssertTrue(String(decoding:cellular,as:UTF8.self).contains("pdp_ip0"))
        XCTAssertFalse(String(decoding:plain,as:UTF8.self).contains("sockopt"))
    }

    func testPhysicalUnderlayBindingRejectsMissingOrUntrustedInterfaceAndEndpoint() throws {
        let config = try XrayVLESSRuntimeConfig.compileValidatedCandidate(candidate(), socksPort:39879)
        for iface in ["", "utun0", "lo0", "en", "pdp_ip", "en-1", "pdp_ip0;utun0", "en999", "pdp_ip999"] {
            XCTAssertThrowsError(try XrayVLESSRuntimeConfig.bindPhysicalUnderlay(
                config, interfaceName:iface, expectedAddress:"example.com", expectedPort:443))
        }
        XCTAssertThrowsError(try XrayVLESSRuntimeConfig.bindPhysicalUnderlay(
            config, interfaceName:"en0", expectedAddress:"other.example", expectedPort:443))
        XCTAssertThrowsError(try XrayVLESSRuntimeConfig.bindPhysicalUnderlay(
            config, interfaceName:"en0", expectedAddress:"example.com", expectedPort:444))
    }

    func testPhysicalUnderlayRejectsExistingSockoptOrUnreviewedExtraOutbound() throws {
        let plain = try XrayVLESSRuntimeConfig.compileValidatedCandidate(candidate(), socksPort:39879)
        for mutation in ["sockopt", "outbound", "protocol"] {
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with:plain) as? [String:Any])
            var out = try XCTUnwrap(root["outbounds"] as? [[String:Any]])
            switch mutation {
            case "sockopt":
                var stream=try XCTUnwrap(out[0]["streamSettings"] as? [String:Any])
                stream["sockopt"]=["interface":"utun0"]
                out[0]["streamSettings"]=stream
            case "outbound":
                out.append(["protocol":"freedom"])
            default:
                out[0]["protocol"]="freedom"
            }
            root["outbounds"]=out
            let changed=try JSONSerialization.data(withJSONObject:root)
            XCTAssertThrowsError(try XrayVLESSRuntimeConfig.bindPhysicalUnderlay(
                changed,interfaceName:"en0",expectedAddress:"example.com",expectedPort:443))
        }
    }

    func testMalformedOversizedAndInvalidPortRejected() throws {
        let profile = try candidate()
        XCTAssertThrowsError(try XrayVLESSRuntimeConfig.prepare(candidate: profile,
            converterResponse: Data(repeating: 32, count: XrayVLESSRuntimeConfig.maxResponseBytes + 1),
            socksPort: 39879))
        XCTAssertThrowsError(try XrayVLESSRuntimeConfig.prepare(candidate: profile,
            converterResponse: Data("{}".utf8), socksPort: 39879))
        for port in [0, 80, 65536] {
            XCTAssertThrowsError(try XrayVLESSRuntimeConfig.prepare(candidate: profile,
                converterResponse: response([converted()]), socksPort: port))
        }
    }
}
