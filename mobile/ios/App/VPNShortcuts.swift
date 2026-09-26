import AppIntents
import NetworkExtension

@MainActor
enum AppRoutingVPNControl {
    static func applyBaseline(_ mode: IOSAppRoutingMode) async throws {
        try await setConnected(mode == .normallyOn)
    }

    static func applySelectedAppEvent(opened: Bool) async throws {
        let store = try ProfileStore()
        let mode = store.iosAppRoutingMode

        let shouldConnect: Bool
        switch (mode, opened) {
        case (.normallyOn, true):
            shouldConnect = false
        case (.normallyOn, false):
            shouldConnect = true
        case (.normallyOff, true):
            shouldConnect = true
        case (.normallyOff, false):
            shouldConnect = false
        }

        try await setConnected(shouldConnect)
    }

    private static func setConnected(_ shouldConnect: Bool) async throws {
        let controller = VPNController()
        await controller.prepare()

        if shouldConnect {
            if controller.status == .disconnecting {
                try await Task.sleep(nanoseconds: 600_000_000)
                await controller.prepare()
            }
            if !controller.isConnectedOrConnecting {
                try await controller.connect()
            }
        } else if controller.isConnectedOrConnecting {
            controller.disconnect()
        }
    }
}

@available(iOS 16.0, *)
struct SelectedAppOpenedIntent: AppIntent {
    static let title: LocalizedStringResource = "Выбранное приложение открыто"
    static let description = IntentDescription(
        "Сообщает APL, что открыто выбранное приложение. APL сам применяет сохранённый режим маршрутизации."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AppRoutingVPNControl.applySelectedAppEvent(opened: true)
        return .result()
    }
}

@available(iOS 16.0, *)
struct SelectedAppClosedIntent: AppIntent {
    static let title: LocalizedStringResource = "Выбранное приложение закрыто"
    static let description = IntentDescription(
        "Сообщает APL, что пользователь вышел из выбранного приложения. APL сам восстанавливает обычное состояние."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AppRoutingVPNControl.applySelectedAppEvent(opened: false)
        return .result()
    }
}

@available(iOS 16.0, *)
struct APLShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SelectedAppOpenedIntent(),
            phrases: ["Выбранное приложение открыто в \(.applicationName)"],
            shortTitle: "Приложение открыто",
            systemImageName: "rectangle.and.hand.point.up.left"
        )
        AppShortcut(
            intent: SelectedAppClosedIntent(),
            phrases: ["Выбранное приложение закрыто в \(.applicationName)"],
            shortTitle: "Приложение закрыто",
            systemImageName: "rectangle.portrait.and.arrow.right"
        )
    }
}
