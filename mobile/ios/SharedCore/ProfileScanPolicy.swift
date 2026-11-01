import Foundation

/// Small, deterministic batches avoid a burst of paid proxy connections.
/// Automatic diagnostics sample a few important profiles; manual scans page
/// through the entire list without launching concurrent network probes.
struct ProfileScanPolicy {
    let automaticLimit = 3
    let manualLimit = 10
    let automaticCooldown: TimeInterval = 180
    let manualCooldown: TimeInterval = 10

    func batch(ids: [UUID], selectedID: UUID?, primaryID: UUID?, favorites: Set<UUID>, manualCursor: Int? = nil) -> [UUID] {
        guard !ids.isEmpty else { return [] }
        if let cursor = manualCursor {
            let start = ((cursor % ids.count) + ids.count) % ids.count
            return (0..<min(manualLimit, ids.count)).map { ids[(start + $0) % ids.count] }
        }
        var ordered: [UUID] = []
        for id in [selectedID, primaryID].compactMap({ $0 }) + ids.filter({ favorites.contains($0) }) + ids {
            if ids.contains(id), !ordered.contains(id) { ordered.append(id) }
            if ordered.count == automaticLimit { break }
        }
        return ordered
    }

    func permitted(now: Date, lastScan: Date?, manual: Bool) -> Bool {
        guard let lastScan else { return true }
        return now.timeIntervalSince(lastScan) >= (manual ? manualCooldown : automaticCooldown)
    }
}
