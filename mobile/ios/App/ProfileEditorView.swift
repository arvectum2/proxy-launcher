import SwiftUI

struct ProfileEditorView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let profile: ProxyProfile?

    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var type: ProxyType
    @State private var username: String
    @State private var password = ""

    init(profile: ProxyProfile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _host = State(initialValue: profile?.host ?? "")
        _port = State(initialValue: profile.map { String($0.port) } ?? "")
        _type = State(initialValue: profile?.type ?? .auto)
        _username = State(initialValue: profile?.username ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Прокси") {
                    TextField("Название", text: $name)
                    TextField("Хост", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Порт", text: $port)
                        .keyboardType(.numberPad)
                    Picker("Тип", selection: $type) {
                        ForEach(ProxyType.allCases) { type in Text(AppL10n.tr(type.label)).tag(type) }
                    }
                }
                Section("Авторизация") {
                    TextField("Логин", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(profile == nil ? "Пароль" : "Новый пароль", text: $password)
                        .accessibilityHint(profile == nil ? "" : "Оставьте пустым, чтобы сохранить прежний пароль")
                }
                if let profile {
                    Section {
                        Button("Удалить профиль", role: .destructive) {
                            model.delete(profile)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(AppL10n.tr(profile == nil ? "Новый прокси" : "Изменить прокси"))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if model.saveProfile(
                            editingID: profile?.id,
                            name: name,
                            host: host,
                            portText: port,
                            type: type,
                            username: username,
                            password: password
                        ) { dismiss() }
                    }
                }
            }
        }
    }
}
