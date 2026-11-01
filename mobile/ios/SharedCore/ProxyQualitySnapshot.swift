import Foundation

struct ProxyLatencySample: Codable, Equatable {
    let latencyMs: Int
    let checkedAt: Date
}

/// Fresh, anonymous measurement data only; never store hosts or credentials.
struct ProxyQualitySnapshot: Codable, Equatable {
    private(set) var samples: [UUID: ProxyLatencySample] = [:]
    static let maxAge: TimeInterval = 600

    mutating func markAvailable(_ id: UUID, latencyMs: Int, at now: Date = Date()) {
        guard (1...30_000).contains(latencyMs) else { return }
        samples[id] = ProxyLatencySample(latencyMs: latencyMs, checkedAt: now)
    }

    mutating func markUnavailable(_ id: UUID) { samples.removeValue(forKey: id) }

    mutating func prune(keeping profileIDs: Set<UUID>) {
        samples = samples.filter { profileIDs.contains($0.key) }
    }

    func freshLatencies(for profileIDs: Set<UUID>, at now: Date = Date()) -> [UUID: Int] {
        samples.compactMapValues { record in
            let age = now.timeIntervalSince(record.checkedAt)
            return age >= -5 && age <= Self.maxAge ? record.latencyMs : nil
        }.filter { profileIDs.contains($0.key) }
    }
}
