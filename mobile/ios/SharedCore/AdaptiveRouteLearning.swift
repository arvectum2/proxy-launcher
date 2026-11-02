import Foundation

/// Local-only adaptive routing evidence; NEVER mutates VPN/IP routes.
/// Direct requires a separately proven, exact-host, non-tunnel egress.
struct AdaptiveRouteLearning: Codable, Equatable {
    enum Failure: String, Codable {
        case proxyTimeout, proxyRefused, proxyAuthentication, tlsApplication, pageTimeout, offline
        var eligible: Bool { self == .proxyTimeout || self == .proxyRefused }
    }
    enum Action: Equatable {
        case keepProxy, verifyDirect(String), unsupportedDirect(String), temporaryDirect(String), revert(String)
    }
    struct Entry: Codable, Equatable {
        var sessionIDs: [String]
        var started: Date
        var last: Date
        var successes: Int
        var lastVerified: Date?
        var lastProbeRequested: Date?
        var expires: Date?
        var networkID: String
    }
    static let window: TimeInterval = 120
    static let lifetime: TimeInterval = 86400
    static let maxHosts = 64
    static let maxActive = 12
    var hosts: [String: Entry] = [:]
    var rejected: Set<String> = []

    private static func validated(_ host: String) -> String? {
        let value = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = try? SiteExclusionPolicy.normalize(value), value == normalized,
              SiteDependencyDiscovery.isScannableHost(value),
              SiteDependencyDiscovery.eligibleForAutomaticBypass(value) else { return nil }
        return normalized
    }

    mutating func prune(at now: Date, networkID: String) {
        hosts = hosts.filter { _, v in
            v.networkID == networkID && v.started <= now &&
            ((v.expires ?? .distantPast) > now || now.timeIntervalSince(v.last) <= Self.window)
        }
        if hosts.count > Self.maxHosts {
            for host in hosts.sorted(by: { $0.value.last < $1.value.last })
                .prefix(hosts.count - Self.maxHosts).map(\.key) { hosts.removeValue(forKey: host) }
        }
    }

    mutating func proxyFailure(host: String, connectionID: String, type: Failure,
                               proxyHealthy: Bool, networkID: String, at now: Date) -> Action {
        prune(at: now, networkID: networkID)
        guard let host = Self.validated(host), !rejected.contains(host),
              type.eligible, proxyHealthy, !connectionID.isEmpty,
              connectionID.count <= 80 else { return .keepProxy }
        var e = hosts[host] ?? Entry(sessionIDs: [], started: now, last: now, successes: 0,
                                     lastVerified: nil, lastProbeRequested: nil, expires: nil, networkID: networkID)
        if now.timeIntervalSince(e.started) > Self.window {
            e = Entry(sessionIDs: [], started: now, last: now, successes: 0,
                      lastVerified: nil, lastProbeRequested: nil, expires: nil, networkID: networkID)
        }
        if !e.sessionIDs.contains(connectionID) { e.sessionIDs.append(connectionID) }
        e.last = now
        let shouldProbe = e.sessionIDs.count >= 2 &&
            (e.lastProbeRequested.map { now.timeIntervalSince($0) >= 60 } ?? true)
        if shouldProbe { e.lastProbeRequested = now }
        hosts[host] = e
        return shouldProbe ? .verifyDirect(host) : .keepProxy
    }

    /// Caller MUST prove a fresh independent direct socket and host-specific
    /// routing. A probe through this same VPN is not independent evidence.
    mutating func comparison(host: String, proxyFailed: Bool, directSucceeded: Bool,
                             independentlyDirect: Bool, exactHostTransport: Bool,
                             networkID: String, at now: Date) -> Action {
        prune(at: now, networkID: networkID)
        guard let host = Self.validated(host), !rejected.contains(host),
              var e = hosts[host], e.networkID == networkID,
              e.sessionIDs.count >= 2 else { return .keepProxy }
        guard proxyFailed, directSucceeded, independentlyDirect else {
            e.successes = 0; e.lastVerified = nil; hosts[host] = e
            return .keepProxy
        }
        guard exactHostTransport else { return .unsupportedDirect(host) }
        guard hosts.values.filter({ ($0.expires ?? .distantPast) > now }).count < Self.maxActive ||
              (e.expires ?? .distantPast) > now else { return .keepProxy }
        if let previous = e.lastVerified, now.timeIntervalSince(previous) < 1 { return .keepProxy }
        e.successes += 1
        e.lastVerified = now
        if e.successes >= 2 { e.expires = now.addingTimeInterval(Self.lifetime) }
        hosts[host] = e
        return e.expires != nil ? .temporaryDirect(host) : .verifyDirect(host)
    }

    func directHosts(networkID: String, exactHostTransport: Bool, at now: Date) -> [String] {
        guard exactHostTransport else { return [] }
        return hosts.compactMap { host, entry in
            entry.networkID == networkID && (entry.expires ?? .distantPast) > now &&
              !rejected.contains(host) ? host : nil
        }.sorted()
    }

    mutating func directFailure(_ host: String) -> Action {
        guard let host = Self.validated(host), var e = hosts[host] else { return .keepProxy }
        e.expires = nil; e.successes = 0; hosts[host] = e
        return .revert(host)
    }
    mutating func reject(_ host: String) {
        guard let host = Self.validated(host) else { return }
        guard rejected.count < 128 || rejected.contains(host) else { return }
        rejected.insert(host); hosts.removeValue(forKey: host)
    }
}
