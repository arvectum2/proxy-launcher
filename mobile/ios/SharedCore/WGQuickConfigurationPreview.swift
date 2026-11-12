import Darwin
import Foundation

/// Inactive wg-quick configuration preview: secrets are validated then discarded.
/// No VPN activation, Keychain persistence or production protocol declaration.
struct WGQuickConfigurationPreview: Equatable {
    enum Format: String { case wireGuard, amneziaWG1 }
    struct Peer: Equatable {
        let endpoint: String
        let allowedIPs: [String]
        let hasPresharedKey: Bool
    }
    let format: Format
    let addresses: [String]
    let dnsServers: [String]
    let peers: [Peer]
    enum Failure: Error, Equatable { case tooLarge, invalid, unsupportedVariant }
    static let maxBytes = 16_384

    private static let interfaceKeys: Set<String> = [
        "privatekey", "address", "dns", "listenport", "mtu"
    ]
    private static let peerKeys: Set<String> = [
        "publickey", "presharedkey", "allowedips", "endpoint", "persistentkeepalive"
    ]
    /// Explicitly preview AWG 1.x fixed headers only. S3/S4/I1/HPK,
    /// randomized header ranges and AWG 2/3 may never fall back to WG.
    private static let awg1Keys: Set<String> = [
        "jc", "jmin", "jmax", "s1", "s2", "h1", "h2", "h3", "h4"
    ]

    static func parse(_ config: String) throws -> WGQuickConfigurationPreview {
        guard config.utf8.count <= maxBytes else { throw Failure.tooLarge }
        guard !config.isEmpty, !config.contains("\0") else { throw Failure.invalid }
        var interface: [String: String]?
        var peers: [[String: String]] = []
        var section = ""
        let lines = config.components(separatedBy: .newlines)
        guard lines.count <= 160 else { throw Failure.tooLarge }
        for raw in lines {
            let line = String(raw.prefix { $0 != "#" })
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.lowercased() == "[interface]" {
                guard interface == nil, section.isEmpty else { throw Failure.invalid }
                interface = [:]; section = "interface"
                continue
            }
            if line.lowercased() == "[peer]" {
                guard interface != nil, !section.isEmpty, peers.count < 8 else {
                    throw Failure.invalid
                }
                peers.append([:]); section = "peer"
                continue
            }
            guard let split = line.firstIndex(of: "="), !section.isEmpty else {
                throw Failure.invalid
            }
            let key = line[..<split].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: split)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            }) else { throw Failure.invalid }
            if section == "interface" {
                guard interfaceKeys.contains(key) || awg1Keys.contains(key) else {
                    throw Failure.unsupportedVariant
                }
                guard interface?[key] == nil else { throw Failure.invalid }
                interface?[key] = value
            } else {
                guard peerKeys.contains(key) else { throw Failure.unsupportedVariant }
                guard peers[peers.count - 1][key] == nil else { throw Failure.invalid }
                peers[peers.count - 1][key] = value
            }
        }
        guard let properties = interface, !peers.isEmpty,
              validKey(properties["privatekey"]),
              let addressValue = properties["address"] else { throw Failure.invalid }
        let addresses = try ranges(addressValue, maxEntries: 8)
        let dns = try ipAddresses(properties["dns"], maxEntries: 8)
        if let port = properties["listenport"] {
            guard let value = UInt16(port), value > 0 else { throw Failure.invalid }
        }
        if let mtu = properties["mtu"] {
            guard let value = Int(mtu), (576...9000).contains(value) else { throw Failure.invalid }
        }
        let presentAWG = Set(properties.keys).intersection(awg1Keys)
        let format: Format
        if presentAWG.isEmpty { format = .wireGuard }
        else {
            guard presentAWG == awg1Keys else { throw Failure.unsupportedVariant }
            try validateAmneziaV1(properties)
            format = .amneziaWG1
        }
        var seen = Set<String>()
        let items: [Peer] = try peers.map { peer in
            guard let pub = peer["publickey"], validKey(pub),
                  seen.insert(pub).inserted,
                  let endpoint = peer["endpoint"], validEndpoint(endpoint),
                  let ips = peer["allowedips"] else { throw Failure.invalid }
            if let psk = peer["presharedkey"], !validKey(psk) { throw Failure.invalid }
            if let keepalive = peer["persistentkeepalive"] {
                guard UInt16(keepalive) != nil else { throw Failure.invalid }
            }
            return Peer(endpoint: endpoint, allowedIPs: try ranges(ips, maxEntries: 16),
                        hasPresharedKey: peer["presharedkey"] != nil)
        }
        return WGQuickConfigurationPreview(format: format, addresses: addresses,
                                           dnsServers: dns, peers: items)
    }

    private static func validKey(_ text: String?) -> Bool {
        guard let text, text.utf8.count == 44,
              let bytes = Data(base64Encoded: text), bytes.count == 32 else { return false }
        return true
    }

    private static func ranges(_ value: String, maxEntries: Int) throws -> [String] {
        let list = value.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !list.isEmpty, list.count <= maxEntries else { throw Failure.invalid }
        for range in list {
            let parts = range.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let prefix = Int(parts[1]),
                  (0...(parts[0].contains(":") ? 128 : 32)).contains(prefix),
                  validIP(parts[0]) else { throw Failure.invalid }
        }
        return list
    }

    private static func ipAddresses(_ text: String?, maxEntries: Int) throws -> [String] {
        guard let text else { return [] }
        let list = text.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !list.isEmpty, list.count <= maxEntries,
              list.allSatisfy(validIP) else { throw Failure.invalid }
        return list
    }

    private static func validIP(_ text: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return text.withCString {
            inet_pton(AF_INET, $0, &ipv4) == 1 || inet_pton(AF_INET6, $0, &ipv6) == 1
        }
    }

    private static func validEndpoint(_ text: String) -> Bool {
        let host: String
        let portString: String
        if text.hasPrefix("["), let end = text.firstIndex(of: "]"),
           text.index(after: end) < text.endIndex, text[text.index(after: end)] == ":" {
            host = String(text[text.index(after: text.startIndex)..<end])
            portString = String(text[text.index(end, offsetBy: 2)...])
            guard host.contains(":"), validIP(host) else { return false }
        } else {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 else { return false }
            host = String(parts[0]); portString = String(parts[1])
            guard validIP(host) || ManagedProfileContract.validDNS(host) else { return false }
        }
        return UInt16(portString).map { $0 > 0 } ?? false
    }

    private static func validateAmneziaV1(_ attributes: [String: String]) throws {
        var values: [String: UInt32] = [:]
        for key in awg1Keys {
            guard let raw = attributes[key], let number = UInt32(raw) else {
                throw Failure.unsupportedVariant
            }
            values[key] = number
        }
        guard let jc = values["jc"], jc <= 16,
              let jmin = values["jmin"], let jmax = values["jmax"],
              jmin <= jmax, jmax <= 1500,
              let s1 = values["s1"], let s2 = values["s2"],
              s1 <= 1000, s2 <= 1000, s1 + 56 != s2,
              let h1 = values["h1"], let h2 = values["h2"],
              let h3 = values["h3"], let h4 = values["h4"],
              Set([h1, h2, h3, h4]).count == 4 else {
            throw Failure.unsupportedVariant
        }
    }
}
