import Foundation

enum AppShared {
    static let appGroup = "VML75VY94V.ru.arvectum.proxylauncher.macos"
    static let providerBundleIdentifier = "ru.arvectum.proxylauncher.macos.PacketTunnel"
    static let defaultsSuite = appGroup
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.17"
    static let keychainService = "ru.arvectum.proxylauncher.macos.credentials"

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
