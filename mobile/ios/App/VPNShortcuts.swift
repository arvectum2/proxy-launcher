import AppIntents
import NetworkExtension

@available(iOS 16.0, *)
private enum ShortcutVPNControl {
    @MainActor
    static func connect() async throws {
        let controller = VPNController()
        await controller.prepare()
        try await controller.connect()
    }

    @MainActor
    static func disconnect() async {
        let controller = VPNController()
        await controller.prepare()
        controller.disconnect()
    }
}

@available(iOS 16.0, *)
struct ConnectAPLIntent: AppIntent {
    static let title: LocalizedStringResource = "Подключить APL"
    static let description = IntentDescription("Подключает Arvectum Proxy Launcher к выбранному прокси.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await ShortcutVPNControl.connect()
        return .result()
    }
}

@available(iOS 16.0, *)
struct DisconnectAPLIntent: AppIntent {
    static let title: LocalizedStringResource = "Отключить APL"
    static let description = IntentDescription("Отключает Arvectum Proxy Launcher.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await ShortcutVPNControl.disconnect()
        return .result()
    }
}

@available(iOS 16.0, *)
struct APLShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectAPLIntent(),
            phrases: ["Подключить \\(.applicationName)", "Включить \\(.applicationName)"],
            shortTitle: "Подключить APL",
            systemImageName: "lock.shield"
        )
        AppShortcut(
            intent: DisconnectAPLIntent(),
            phrases: ["Отключить \\(.applicationName)", "Выключить \\(.applicationName)"],
            shortTitle: "Отключить APL",
            systemImageName: "lock.open"
        )
    }
}
