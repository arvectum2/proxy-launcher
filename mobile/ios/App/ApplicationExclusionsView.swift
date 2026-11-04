import SwiftUI

struct ApplicationExclusionsView: View {
    @Environment(\.dismiss) private var dismiss

#if targetEnvironment(macCatalyst)
    var body: some View {
        NavigationView {
            List {
                Section("Исключения приложений") {
                    Label("Настройка по открытию и закрытию приложений доступна на iPhone.", systemImage: "iphone")
                    Text("Mac Catalyst сохраняет общий раздел Настройки, но не имитирует iOS Shortcuts: на macOS применяются только реально поддерживаемые механизмы маршрутизации.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Исключения приложений")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }
#else
    @State private var mode: IOSAppRoutingMode = .normallyOn
    @State private var storageError: String?

    var body: some View {
        NavigationView {
            List {
                Section(AppL10n.tr("Как работать с приложениями")) {
                    Picker("Режим", selection: $mode) {
                        ForEach(IOSAppRoutingMode.allCases) { item in
                            Text(AppL10n.tr(item.title)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { saveAndApplyMode($0) }
                    Text(AppL10n.tr(modeExplanation))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(AppL10n.tr("Настроить один раз")) {
                    Link(destination: URL(string: "shortcuts://create-shortcut")!) {
                        Label(AppL10n.tr("Открыть «Команды»"), systemImage: "arrow.up.forward.app")
                    }
                    Text(AppL10n.tr("Создайте две автоматизации для нужных приложений: «Открыто» → APL «Приложение открыто», «Закрыто» → APL «Приложение закрыто». Выберите «Немедленно»."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let storageError {
                    Section { Text(storageError).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(AppL10n.tr("Автоматизация"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadAndApplyMode() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }

    private var modeExplanation: String {
        switch mode {
        case .normallyOn:
            return "APL обычно включён. Для выбранных приложений — временно отключается."
        case .normallyOff:
            return "APL обычно выключен. Для выбранных приложений — временно включается."
        }
    }

    private func loadAndApplyMode() {
        do {
            let storedMode = try ProfileStore().iosAppRoutingMode
            mode = storedMode
            storageError = nil
            Task { @MainActor in
                do {
                    try await AppRoutingVPNControl.applyBaseline(storedMode)
                } catch {
                    storageError = error.localizedDescription
                }
            }
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func saveAndApplyMode(_ newValue: IOSAppRoutingMode) {
        do {
            let store = try ProfileStore()
            store.iosAppRoutingMode = newValue
            storageError = nil
            Task { @MainActor in
                do {
                    try await AppRoutingVPNControl.applyBaseline(newValue)
                } catch {
                    storageError = error.localizedDescription
                }
            }
        } catch {
            storageError = error.localizedDescription
        }
    }
#endif
}
