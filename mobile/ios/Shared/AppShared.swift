import Foundation

enum AppShared {
    static let appGroup = "group.ru.arvectum.proxylauncher.ios"
    static let providerBundleIdentifier = "ru.arvectum.proxylauncher.ios.PacketTunnel"
    static let defaultsSuite = appGroup
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    #if APL_PRODUCT_UI_QA
    static let nativeCredentialServicePrefix = "ru.arvectum.proxylauncher.ios.synthetic-ui-qa."
    #elseif APL_PRODUCT_OWNER_QA
    static let nativeCredentialServicePrefix = "ru.arvectum.proxylauncher.ios.synthetic-owner-qa."
    #else
    static let nativeCredentialServicePrefix = "ru.arvectum.proxylauncher.ios."
    #endif
    #if APL_PRODUCT_UI_QA
    static let keychainService = "ru.arvectum.proxylauncher.ios.synthetic-ui-qa.credentials"
    #else
    static let keychainService = "ru.arvectum.proxylauncher.ios.credentials"
    #endif
    static let keychainAccessGroup: String? = "VML75VY94V.ru.arvectum.proxylauncher.ios.shared"
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
