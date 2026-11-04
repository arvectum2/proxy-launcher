import SwiftUI

/// In-app instructions follow the chosen app language. App Intents themselves
/// are localized by iOS using QuickActions.strings and system language.
enum QuickActionsCopy {
    static func text(_ ru: String, en: String) -> String {
        // App-level language controls this help sheet independently of the
        // system language used by iOS for the actual App Intents labels.
        let value = AppL10n.tr(ru)
        return value == ru && AppL10n.effectiveLanguage != "ru" ? en : value
    }

    static func action(_ key: String) -> String {
        for code in [AppL10n.effectiveLanguage, "en"] {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            let value = bundle.localizedString(forKey: key, value: key, table: "QuickActions")
            if value != key || code == "ru" { return value }
        }
        return key
    }
}

struct QuickActionsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(QuickActionsCopy.text(
                        "В приложении «Команды» добавьте любое из трёх действий APL. Они выполняются только по вашему запуску и используют сохранённые настройки прокси.",
                        en: "Add any of these APL actions in Shortcuts. They run only when you trigger them and use your saved proxy settings."))
                        .font(.footnote)
                    Label(QuickActionsCopy.action("Подключить APL"), systemImage: "network")
                    Label(QuickActionsCopy.action("Отключить APL"), systemImage: "network.slash")
                    Label(QuickActionsCopy.action("Переключить APL"), systemImage: "arrow.triangle.2.circlepath")
                    Link(destination: URL(string: "shortcuts://")!) {
                        Label(QuickActionsCopy.text("Открыть «Команды»", en: "Open Shortcuts"),
                              systemImage: "arrow.up.forward.app")
                    }
                    .accessibilityIdentifier("quickActions.openShortcuts")
                } header: {
                    Text(QuickActionsCopy.text("Быстрые команды VPN", en: "VPN quick actions"))
                } footer: {
                    Text(QuickActionsCopy.text(
                        "Доступно с iOS 16. При отключении сети или неготовности VPN команда сообщит об ошибке. Команды не добавляют и не покупают прокси.",
                        en: "Requires iOS 16. Commands report an error if VPN is unavailable. They do not create or purchase proxies."))
                }
            }
            .navigationTitle(QuickActionsCopy.text("Быстрые команды VPN", en: "VPN quick actions"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppL10n.tr("Готово")) { dismiss() }
                }
            }
        }
    }
}
