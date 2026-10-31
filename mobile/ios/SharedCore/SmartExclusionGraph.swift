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
        for edge in edges where edge.lastSeen <= now && now.timeIntervalSince(edge.lastSeen) < Self.ttl {
            guard Self.validChild(edge.host, for: edge.parent),
                  Self.root(edge.parent) == edge.parent else { continue }
            if let previous = byID[edge.id] {
                // Conflicting duplicate decisions must not silently approve.
                var kept = edge.lastSeen > previous.lastSeen ? edge : previous
                if edge.decision != previous.decision { kept.decision = .pending }
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
        return Self(edges: result)
    }
    mutating func observe(parent raw: String, html: [String], network: [String], at now: Date = Date()) throws {
        guard let parent = Self.root(raw) else { throw SmartGraphError.invalidParent }
        let htmlSet = Set(html.filter { Self.validChild($0, for: parent) })
        let networkSet = Set(network.filter { Self.validChild($0, for: parent) })
        let hosts = htmlSet.union(networkSet)
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
    mutating func set(_ decision: SmartDecision, parent raw: String, child: String) throws {
        guard let root = Self.root(raw), Self.validChild(child, for: root),
              let i = edges.firstIndex(where: { $0.parent == root && $0.host == child }) else {
            throw SmartGraphError.invalidChild
        }
        edges[i].decision = decision
    }
    mutating func remove(parent raw: String, child: String? = nil) {
        guard let root = Self.root(raw) else { return }
        edges.removeAll { $0.parent == root && (child == nil || $0.host == child) }
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
