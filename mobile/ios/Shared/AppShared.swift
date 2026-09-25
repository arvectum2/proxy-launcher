import Foundation

enum AppShared {
    static let appGroup = "group.ru.arvectum.proxylauncher.ios"
    static let providerBundleIdentifier = "ru.arvectum.proxylauncher.ios.PacketTunnel"
    static let defaultsSuite = appGroup
    static let version = "0.1.19"
    static let keychainService = "ru.arvectum.proxylauncher.ios.credentials"

    static var keychainAccessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "APLKeychainAccessGroup") as? String
    }
}

struct TunnelConfiguration: Codable {
    var selectedProfileID: UUID?
    var automaticSelection: Bool
    var primaryProfileID: UUID?
    var restorePolicy: PrimaryRestorePolicy
    var siteExclusions: [String]
    var lastAutoProfileID: UUID?
    var recentlyFailedProfileID: UUID?
    var recentlyFailedAt: Date?
    var lastFailoverAt: Date?
}
