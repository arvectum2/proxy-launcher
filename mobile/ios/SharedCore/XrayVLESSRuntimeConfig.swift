import Darwin
import Foundation

/// In-memory-only runtime configuration for the pinned libXray v26.11.9
/// converter. No runtime invocation, credential storage or production
/// transport enablement. Reject unknown fields rather than passing through
/// a converter-supplied routing policy, listeners or fallback outbounds.
enum XrayVLESSRuntimeConfig {
    enum Failure: Error, Equatable {
        case invalidPort, invalidEndpoint, invalidKey, invalidConverterResponse, invalidConfigurationForUnderlay
    }

    static let maxResponseBytes = 64 * 1024
    private static let outlet = "apl-vless"

    static func prepare(candidate: VLESSRealityShareLink,
                        converterResponse: Data, socksPort: Int) throws -> Data {
        guard (1024...65535).contains(socksPort) else { throw Failure.invalidPort }
        let host = candidate.serverHost.lowercased()
        guard validEndpoint(host) else { throw Failure.invalidEndpoint }
        guard candidate.publicKey.count == 32,
              candidate.publicKey.contains(where: { $0 != 0 }) else { throw Failure.invalidKey }

        let key = candidate.publicKey.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let id = candidate.userID.uuidString.lowercased()
        let flow = candidate.visionFlow ? "xtls-rprx-vision" : ""

        guard converterResponse.count <= maxResponseBytes,
              let root = try? JSONSerialization.jsonObject(with: converterResponse) as? [String: Any],
              Set(root.keys).isSubset(of: ["success", "data", "error"]),
              root["success"] as? Bool == true,
              let data = root["data"] as? [String: Any],
              Set(data.keys) == ["outbounds"],
              let outbounds = data["outbounds"] as? [[String: Any]],
              outbounds.count == 1,
              let converted = outbounds.first,
              Set(converted.keys).isSubset(of: ["protocol", "settings", "streamSettings", "tag"]),
              converted["protocol"] as? String == "vless",
              let settings = converted["settings"] as? [String: Any],
              Set(settings.keys).isSubset(of: ["address", "port", "id", "encryption", "flow"]),
              (settings["address"] as? String)?.lowercased() == host,
              settings["port"] as? Int == candidate.serverPort,
              (settings["id"] as? String)?.lowercased() == id,
              settings["encryption"] as? String == "none",
              (settings["flow"] as? String ?? "") == flow,
              let stream = converted["streamSettings"] as? [String: Any],
              Set(stream.keys) == ["network", "security", "realitySettings"],
              ["tcp", "raw"].contains(stream["network"] as? String ?? ""),
              stream["security"] as? String == "reality",
              let reality = stream["realitySettings"] as? [String: Any],
              Set(reality.keys).isSubset(of: ["fingerprint", "password", "serverName", "shortId"]),
              reality["fingerprint"] as? String == candidate.fingerprint,
              reality["password"] as? String == key,
              (reality["serverName"] as? String)?.lowercased() == candidate.serverName,
              (reality["shortId"] as? String ?? "").lowercased() == candidate.shortID.lowercased()
        else { throw Failure.invalidConverterResponse }

        return try compileValidatedCandidate(candidate,socksPort:socksPort)
    }

    /// Deterministic config from the strict parser. Pinned runtime testXray
    /// remains mandatory before isolated start. No activation authority.
    static func compileValidatedCandidate(_ candidate: VLESSRealityShareLink, socksPort: Int, datagramReview:Bool = false) throws -> Data {
        guard (1024...65535).contains(socksPort) else { throw Failure.invalidPort }
        let host = candidate.serverHost.lowercased()
        guard validEndpoint(host) else { throw Failure.invalidEndpoint }
        guard candidate.publicKey.count == 32, candidate.publicKey.contains(where:{$0 != 0}) else { throw Failure.invalidKey }
        let key = candidate.publicKey.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        let id = candidate.userID.uuidString.lowercased()
        let flow = candidate.visionFlow ? "xtls-rprx-vision" : ""
        // Never reuse the returned object. Reconstruct just the verified
        // values, discard the user's display tag, and use a fixed sole route.
        var verifiedSettings: [String: Any] = [
            "address": host, "port": candidate.serverPort,
            "id": id, "encryption": "none"
        ]
        if candidate.visionFlow { verifiedSettings["flow"] = flow }
        let config: [String: Any] = [
            "log": ["loglevel": "none"],
            "inbounds": [[
                "tag": "apl-local", "listen": "127.0.0.1",
                "port": socksPort, "protocol": "socks",
                "settings": datagramReview ? ["auth":"noauth","udp":true,"ip":"127.0.0.1"] : ["auth":"noauth","udp":false]
            ]],
            "outbounds": [[
                "tag": outlet, "protocol": "vless",
                "settings": verifiedSettings,
                "streamSettings": [
                    "network": "raw", "security": "reality",
                    "realitySettings": [
                        "fingerprint": candidate.fingerprint, "password": key,
                        "serverName": candidate.serverName,
                        "shortId": candidate.shortID.lowercased()
                    ]
                ]
            ]],
            "routing": [
                "domainStrategy": "AsIs",
                "rules": [["type": "field", "inboundTag": ["apl-local"],
                           "outboundTag": outlet]]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
    }

    /// Physical iOS PacketTunnel only: pin the Xray TCP underlay to the
    /// OS-confirmed Wi-Fi/cellular interface *before* installing default
    /// tunnel routes. The Xray Darwin dialer applies IP_BOUND_IF, not an
    /// endpoint-wide excluded NE route (which would leak other app traffic).
    /// Never accept an interface name from an imported profile or URI.
    static func bindPhysicalUnderlay(_ config: Data, interfaceName: String,
                                    expectedAddress: String, expectedPort: UInt16) throws -> Data {
        let allowed: Bool
        if interfaceName.hasPrefix("en") {
            let suffix = interfaceName.dropFirst(2)
            allowed = !suffix.isEmpty && suffix.count <= 2 && suffix.allSatisfy { $0.isASCII && $0.isNumber }
        } else if interfaceName.hasPrefix("pdp_ip") {
            let suffix = interfaceName.dropFirst(6)
            allowed = !suffix.isEmpty && suffix.count <= 2 && suffix.allSatisfy { $0.isASCII && $0.isNumber }
        } else {
            allowed = false
        }
        guard allowed, config.count <= maxResponseBytes,
              var root = try? JSONSerialization.jsonObject(with: config) as? [String: Any],
              Set(root.keys) == Set(["inbounds", "outbounds", "routing", "log"]),
              let inbounds = root["inbounds"] as? [[String: Any]], inbounds.count == 1,
              inbounds[0]["protocol"] as? String == "socks",
              inbounds[0]["listen"] as? String == "127.0.0.1",
              inbounds[0]["port"] as? Int == 39879,
              let outbounds = root["outbounds"] as? [[String: Any]], outbounds.count == 1,
              var outbound = outbounds.first,
              outbound["tag"] as? String == outlet,
              outbound["protocol"] as? String == "vless",
              let settings = outbound["settings"] as? [String: Any],
              settings["address"] as? String == expectedAddress,
              settings["port"] as? Int == Int(expectedPort),
              var stream = outbound["streamSettings"] as? [String: Any],
              stream["network"] as? String == "raw",
              stream["security"] as? String == "reality",
              stream["realitySettings"] is [String: Any],
              stream["sockopt"] == nil else { throw Failure.invalidConfigurationForUnderlay }
        stream["sockopt"] = ["interface": interfaceName]
        outbound["streamSettings"] = stream
        root["outbounds"] = [outbound]
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func validEndpoint(_ host: String) -> Bool {
        if ManagedProfileContract.validDNS(host) { return true }
        var v4 = in_addr()
        var v6 = in6_addr()
        return host.withCString {
            inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1
        }
    }
}
