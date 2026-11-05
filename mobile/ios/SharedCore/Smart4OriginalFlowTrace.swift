import Foundation

/// Volatile, fixed-QA-host-only diagnostic from the native tun2proxy callback.
/// Neither client-side events nor a positive socket prove external egress.
struct Smart4OriginalFlowTrace {
    static let maxFlows = 32
    static let lifetime: TimeInterval = 60

    struct Summary: Equatable {
        let observedFlows: Int
        let proxyHandshakeAccepted: Int
        let originalDirectPayload: Int
        let conflicted: Int
        let inconclusive: Int
        let overflowed: Bool
        // Must be linked to a trusted external receipt in a separate gate.
        let externalEgressVerified = false
    }

    private enum LabAlias: Equatable {
        case primary, sharedIPNeighbor, ipv6Neighbor, syntheticOrigin

        init?(host: String) {
            switch host {
            case "www.apple.com": self = .primary
            case "www.apple.com.cn": self = .sharedIPNeighbor
            case "ipv6.l.google.com": self = .ipv6Neighbor
            case "start.qa-example.test": self = .syntheticOrigin
            default: return nil
            }
        }
    }

    private struct Entry {
        let alias: LabAlias
        let started: Date
        var last: Date
        var events: Set<Int32> = []
        var conflicted = false

        var originalRecoveredWithPayload: Bool {
            !conflicted && events.contains(7) && events.contains(8) &&
                events.contains(9) && (events.contains(10) != events.contains(11)) &&
                !events.contains(0) && !events.contains(5)
        }
        var proxyHandshake: Bool {
            !conflicted && events.contains(0) && !events.contains(7) &&
                !events.contains(6) && !events.contains(8) && !events.contains(9)
        }
    }

    private var flows: [UInt64: Entry] = [:]
    private var overflowed = false

    /// Uses original engine connection ID, not an invented app-side flow ID.
    /// Only fixed QA aliases are retained in memory; never raw host/IP/token.
    mutating func record(host: String, connectionID: UInt64, event: Int32,
                         at now: Date = Date()) {
        guard connectionID != 0, let alias = LabAlias(host: host),
              (0...11).contains(event) else { return }
        expire(at: now)
        if var entry = flows[connectionID] {
            if alias != entry.alias || now < entry.last ||
                now > entry.started.addingTimeInterval(Self.lifetime) {
                entry.conflicted = true
            }
            // These native events are unique per original TCP flow. Repeated
            // recovery, physical family, or first payload is ambiguous.
            if [6, 7, 8, 9, 10, 11].contains(event) && entry.events.contains(event) {
                entry.conflicted = true
            }
            if (event == 8 || event == 9) && !entry.events.contains(7) {
                entry.conflicted = true
            }
            entry.events.insert(event)
            if entry.events.contains(10) && entry.events.contains(11) {
                entry.conflicted = true
            }
            entry.last = max(entry.last, now)
            flows[connectionID] = entry
        } else {
            guard flows.count < Self.maxFlows else {
                overflowed = true
                return
            }
            // Bare native recovery/payload claims without earlier callback
            // state cannot establish one original captured client stream.
            let ambiguous = event == 7 || event == 8 || event == 9
            flows[connectionID] = Entry(alias: alias, started: now, last: now,
                                        events: [event], conflicted: ambiguous)
        }
    }

    /// Counts only. App/UI may never persist flow IDs, hostnames, IP or payloads.
    func summary(at now: Date = Date()) -> Summary {
        let active = flows.values.filter {
            now >= $0.last && now.timeIntervalSince($0.last) <= Self.lifetime
        }
        let proxy = active.filter(\.proxyHandshake).count
        let direct = active.filter(\.originalRecoveredWithPayload).count
        let conflicts = active.filter(\.conflicted).count
        return Summary(observedFlows: active.count, proxyHandshakeAccepted: proxy,
                       originalDirectPayload: direct, conflicted: conflicts,
                       inconclusive: active.count - proxy - direct - conflicts,
                       overflowed: overflowed)
    }

    mutating func reset() {
        flows.removeAll(keepingCapacity: false)
        overflowed = false
    }

    private mutating func expire(at now: Date) {
        flows = flows.filter { _, entry in
            now.timeIntervalSince(entry.last) <= Self.lifetime
        }
    }
}
