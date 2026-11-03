import Foundation

/// Discovery is evidence, not permission to bypass the user's proxy.
enum SmartEvidence: String, Codable {
    case html, network, both
    var description: String {
        switch self {
        case .both: return "HTML и сеть · высокая уверенность"
        case .html: return "Ресурс HTML · средняя уверенность"
        case .network: return "Сетевой запрос · средняя уверенность"
        }
    }
}
enum SmartDecision: String, Codable {
    case pending, approved, rejected
    var label: String {
        switch self {
        case .pending: return "Ожидает"
        case .approved: return "Прямой"
        case .rejected: return "Отклонён"
        }
    }
}
struct SmartDependency: Codable, Equatable, Identifiable {
    let parent: String
    let host: String
    var evidence: SmartEvidence
    var decision: SmartDecision
    var lastSeen: Date
    /// User explicitly linked this host to a parent site. Optional for old stored graphs.
    var userLinked: Bool? = nil
    var id: String { parent + "|" + host }
}
enum SmartGraphError: LocalizedError {
    case invalidParent, invalidChild, tooMany
    var errorDescription: String? {
        switch self {
        case .invalidParent: return "Некорректный домен сайта"
        case .invalidChild: return "Связанный домен не принадлежит сайту"
        case .tooMany: return "Превышен безопасный предел связанных доменов"
        }
    }
}
struct SmartExclusionGraph: Codable, Equatable {
    static let ttl: TimeInterval = 7 * 86400
    var edges: [SmartDependency] = []
    /// Explicit removals are tombstones: a rescan must not silently resurrect
    /// a deleted child. Optional for decoding graphs from previous versions.
    var suppressed: [String]? = nil
    static func root(_ site: String) -> String? {
        guard let s = try? SiteExclusionPolicy.normalize(site),
              SiteDependencyDiscovery.isScannableHost(s) else { return nil }
        return s.hasPrefix("www.") ? String(s.dropFirst(4)) : s
    }
    static func validChild(_ child: String, for parent: String) -> Bool {
        guard let root = root(parent),
              let h = try? SiteExclusionPolicy.normalize(child),
              h == child, SiteDependencyDiscovery.isScannableHost(h) else { return false }
        return h != root && h != "www." + root && h.hasSuffix("." + root)
    }
    func pruned(at now: Date = Date()) -> Self {
        // Treat persistence as potentially malformed: do not let duplicate
        // IDs, unbounded parents or arbitrary child names expand direct routes.
        var byID: [String: SmartDependency] = [:]
        for edge in edges where edge.lastSeen <= now &&
                (edge.userLinked == true || now.timeIntervalSince(edge.lastSeen) < Self.ttl) {
            let validObserved = Self.validChild(edge.host, for: edge.parent)
            let validExplicit = edge.userLinked == true &&
                SiteDependencyDiscovery.isScannableHost(edge.host) &&
                edge.host != edge.parent && edge.host != "www." + edge.parent
            guard (validObserved || validExplicit),
                  Self.root(edge.parent) == edge.parent else { continue }
            if let previous = byID[edge.id] {
                // Conflicting duplicate decisions must not silently approve.
                var kept = edge.lastSeen > previous.lastSeen ? edge : previous
                if edge.decision != previous.decision || edge.userLinked != previous.userLinked {
                    kept.decision = .pending
                    kept.userLinked = nil
                }
                byID[edge.id] = kept
            } else { byID[edge.id] = edge }
        }
        var result: [SmartDependency] = []
        var parents: Set<String> = []
        var counts: [String: Int] = [:]
        for edge in byID.values.sorted(by: { $0.id < $1.id }) {
            if !parents.contains(edge.parent) && parents.count >= SiteExclusionPolicy.maxEntries { continue }
            guard counts[edge.parent, default: 0] < SiteDependencyDiscovery.maxCandidates else { continue }
            result.append(edge)
            parents.insert(edge.parent)
            counts[edge.parent, default: 0] += 1
        }
        let denies = Array(Set((suppressed ?? []).filter { identifier in
            let parts = identifier.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 2 else { return false }
            let parent = String(parts[0]), host = String(parts[1])
            return Self.root(parent) == parent && SiteDependencyDiscovery.isScannableHost(host)
        })).sorted().prefix(SiteExclusionPolicy.maxEntries * SiteDependencyDiscovery.maxCandidates)
        return Self(edges: result, suppressed: Array(denies))
    }
    mutating func observe(parent raw: String, html: [String], network: [String], at now: Date = Date()) throws {
        guard let parent = Self.root(raw) else { throw SmartGraphError.invalidParent }
        let htmlSet = Set(html.filter { Self.validChild($0, for: parent) })
        let networkSet = Set(network.filter { Self.validChild($0, for: parent) })
        let hosts = htmlSet.union(networkSet).filter { host in
            !(suppressed ?? []).contains(parent + "|" + host)
        }
        guard hosts.count <= SiteDependencyDiscovery.maxCandidates else { throw SmartGraphError.tooMany }
        var proposed = pruned(at: now)
        guard Set(proposed.edges.map(\.parent)).union([parent]).count <= SiteExclusionPolicy.maxEntries else {
            throw SmartGraphError.tooMany
        }
        for host in hosts.sorted() {
            let evidence: SmartEvidence = htmlSet.contains(host) && networkSet.contains(host)
                ? .both : htmlSet.contains(host) ? .html : .network
            if let i = proposed.edges.firstIndex(where: { $0.parent == parent && $0.host == host }) {
                proposed.edges[i].evidence = evidence
                proposed.edges[i].lastSeen = now
            } else {
                guard proposed.edges.filter({ $0.parent == parent }).count < SiteDependencyDiscovery.maxCandidates else {
                    throw SmartGraphError.tooMany
                }
                proposed.edges.append(.init(parent: parent, host: host, evidence: evidence,
                                            decision: .pending, lastSeen: now))
            }
        }
        proposed.edges.sort { $0.id < $1.id }
        self = proposed
    }
    /// Automatically include only first-party hosts observed in BOTH the
    /// rendered page and actual runtime resource requests. An unobserved,
    /// rejected, cross-site or ambiguous host is never granted DIRECT.
    /// Preserve both existing user decisions and the 32-rule hard limit.
    @discardableResult
    mutating func approveStrongFirstParty(parent raw: String, manual: [String],
                                          at now: Date = Date()) -> [String] {
        guard let parent = Self.root(raw),
              (try? SiteExclusionPolicy.normalizeAll(manual))?
                  .contains(where: { Self.root($0) == parent }) == true else { return [] }
        var approved: [String] = []
        for i in edges.indices where edges[i].parent == parent &&
                edges[i].decision == .pending && edges[i].evidence == .both &&
                Self.validChild(edges[i].host, for: parent) &&
                SiteDependencyDiscovery.eligibleForAutomaticBypass(edges[i].host) {
            edges[i].decision = .approved
            if (try? effective(manual: manual, at: now)) != nil {
                approved.append(edges[i].host)
            } else {
                edges[i].decision = .pending
            }
        }
        return approved.sorted()
    }

    /// User-initiated links can include external authentication domains. They
    /// are never inferred from a third-party resource or shared CDN IP.
    mutating func addUserLink(parent raw: String, child rawChild: String,
                              at now: Date = Date()) throws {
        guard let parent = Self.root(raw),
              let child = try? SiteExclusionPolicy.normalize(rawChild),
              SiteDependencyDiscovery.isScannableHost(child),
              child != parent, child != "www." + parent else { throw SmartGraphError.invalidChild }
        var proposed = pruned(at: now)
        proposed.suppressed?.removeAll { $0 == parent + "|" + child }
        if let i = proposed.edges.firstIndex(where: { $0.parent == parent && $0.host == child }) {
            proposed.edges[i].decision = .approved
            proposed.edges[i].userLinked = true
            proposed.edges[i].lastSeen = now
        } else {
            guard proposed.edges.filter({ $0.parent == parent }).count < SiteDependencyDiscovery.maxCandidates,
                  Set(proposed.edges.map { $0.parent }).union([parent]).count <= SiteExclusionPolicy.maxEntries
            else { throw SmartGraphError.tooMany }
            proposed.edges.append(.init(parent: parent, host: child, evidence: .network,
                                        decision: .approved, lastSeen: now, userLinked: true))
        }
        proposed.edges.sort { $0.id < $1.id }
        self = proposed
    }

    mutating func set(_ decision: SmartDecision, parent raw: String, child: String) throws {
        guard let root = Self.root(raw),
              let i = edges.firstIndex(where: { $0.parent == root && $0.host == child }),
              Self.validChild(child, for: root) ||
                (edges[i].userLinked == true && SiteDependencyDiscovery.isScannableHost(child)) else {
            throw SmartGraphError.invalidChild
        }
        edges[i].decision = decision
        // A user denial must survive rescans and expiry.
        if decision == .rejected { edges[i].userLinked = true }
    }
    mutating func remove(parent raw: String, child: String? = nil) {
        guard let root = Self.root(raw) else { return }
        if let child {
            guard SiteDependencyDiscovery.isScannableHost(child) else { return }
            let id = root + "|" + child
            if !(suppressed ?? []).contains(id) { suppressed = (suppressed ?? []) + [id] }
            edges.removeAll { $0.parent == root && $0.host == child }
        } else {
            edges.removeAll { $0.parent == root }
            suppressed = (suppressed ?? []).filter { !$0.hasPrefix(root + "|") }
        }
    }
    func approved(at now: Date = Date()) -> [String] {
        Array(Set(pruned(at: now).edges.filter { $0.decision == .approved }.map(\.host))).sorted()
    }
    func effective(manual: [String], at now: Date = Date()) throws -> [String] {
        let normalized = try SiteExclusionPolicy.normalizeAll(manual)
        let activeParents = Set(normalized.compactMap(Self.root))
        let approvedChildren = pruned(at: now).edges.filter {
            $0.decision == .approved && activeParents.contains($0.parent)
        }.map(\.host)
        return try SiteExclusionPolicy.normalizeAll(normalized + approvedChildren)
    }
}
