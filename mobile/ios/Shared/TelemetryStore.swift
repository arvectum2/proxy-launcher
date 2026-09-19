import Foundation

struct TunnelEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let type: String
    let profileName: String?
    let detail: String?

    init(type: String, profileName: String? = nil, detail: String? = nil) {
        id = UUID()
        timestamp = Date()
        self.type = type
        self.profileName = profileName
        self.detail = detail
    }
}

final class TelemetryStore {
    private let defaults = UserDefaults(suiteName: AppShared.defaultsSuite)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let key = "tunnel_events_v1"

    func append(_ event: TunnelEvent) {
        guard let defaults else { return }
        var events = list(limit: 40)
        events.insert(event, at: 0)
        events = Array(events.prefix(40))
        if let data = try? encoder.encode(events) { defaults.set(data, forKey: key) }
    }

    func list(limit: Int = 20) -> [TunnelEvent] {
        guard let defaults,
              let data = defaults.data(forKey: key),
              let events = try? decoder.decode([TunnelEvent].self, from: data) else { return [] }
        return Array(events.prefix(limit))
    }

    func clear() {
        defaults?.removeObject(forKey: key)
    }
}
