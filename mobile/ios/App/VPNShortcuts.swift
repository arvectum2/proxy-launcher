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

    private static var explicitQuickActionInProgress = false

    /// Called only from a user-invoked Shortcuts action, never from a
    /// background intent registration or a widget rendering callback.
    static func applyQuickAction(_ action: QuickVPNAction) async throws {
        guard !explicitQuickActionInProgress else {
            throw NSError(domain: "ArvectumVPN", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Другая команда VPN ещё выполняется"])
        }
        explicitQuickActionInProgress = true
        defer { explicitQuickActionInProgress = false }

        let controller = VPNController()
        await controller.prepare()
        let state: QuickVPNConnectionState
        switch controller.status {
        case .connected, .reasserting: state = .connected
        case .connecting: state = .connecting
        case .disconnecting: state = .disconnecting
        default: state = .disconnected
        }
        switch QuickVPNActionPolicy.decide(action: action, state: state) {
        case .noChange: return
        case .busy:
            throw NSError(domain: "ArvectumVPN", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "VPN ещё отключается. Повторите действие позднее."])
        case .connect:
            try await controller.connect()
        case .disconnect:
            try await controller.disconnectAndWait()
        }
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
struct ConnectAPLIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("Подключить APL", table: "QuickActions")
    static let description = IntentDescription("Подключает VPN APL с ранее сохранёнными настройками прокси.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AppRoutingVPNControl.applyQuickAction(.connect)
        return .result()
    }
}

@available(iOS 16.0, *)
struct DisconnectAPLIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("Отключить APL", table: "QuickActions")
    static let description = IntentDescription("Запрашивает отключение текущего VPN APL.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AppRoutingVPNControl.applyQuickAction(.disconnect)
        return .result()
    }
}

@available(iOS 16.0, *)
struct ToggleAPLIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("Переключить APL", table: "QuickActions")
    static let description = IntentDescription("Подключает или отключает APL согласно текущему состоянию VPN.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AppRoutingVPNControl.applyQuickAction(.toggle)
        return .result()
    }
}

@available(iOS 16.0, *)
struct APLShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectAPLIntent(),
            phrases: ["Подключить VPN в \(.applicationName)"],
            shortTitle: LocalizedStringResource("Подключить APL", table: "QuickActions"),
            systemImageName: "network"
        )
        AppShortcut(
            intent: DisconnectAPLIntent(),
            phrases: ["Отключить VPN в \(.applicationName)"],
            shortTitle: LocalizedStringResource("Отключить APL", table: "QuickActions"),
            systemImageName: "network.slash"
        )
        AppShortcut(
            intent: ToggleAPLIntent(),
            phrases: ["Переключить VPN в \(.applicationName)"],
            shortTitle: LocalizedStringResource("Переключить APL", table: "QuickActions"),
            systemImageName: "arrow.triangle.2.circlepath"
        )
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
