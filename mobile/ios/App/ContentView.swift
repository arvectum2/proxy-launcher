import SwiftUI
import NetworkExtension

private enum Brand {
    static let navy = Color(red: 0, green: 20/255, blue: 50/255)
    static let mint = Color(red: 0, green: 200/255, blue: 160/255)
    static let mintLight = Color(red: 120/255, green: 250/255, blue: 230/255)
    static let softGray = Color(red: 200/255, green: 210/255, blue: 220/255)
    static let graphite = Color(red: 40/255, green: 50/255, blue: 70/255)
}

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var editorProfile: ProxyProfile?
    @State private var showNewProfile = false
    @State private var showExclusions = false
    @State private var showJournal = false

    var body: some View {
        ZStack {
            Brand.navy.ignoresSafeArea()
            VStack(spacing: 12) {
                header
                Spacer(minLength: 10)
                powerArea
                Spacer(minLength: 10)
                proxyCard
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .task { await model.prepare() }
        .sheet(isPresented: $showNewProfile) {
            ProfileEditorView(profile: nil).environmentObject(model)
        }
        .sheet(item: $editorProfile) { profile in
            ProfileEditorView(profile: profile).environmentObject(model)
        }
        .sheet(isPresented: $showExclusions) {
            ExclusionsView().environmentObject(model)
        }
        .sheet(isPresented: $showJournal) {
            JournalView().environmentObject(model)
        }
        .alert("Arvectum Proxy Launcher", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 7) {
            Text("AV")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Brand.mint)
            Text("Arvectum Proxy Launcher")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Brand.mint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(AppShared.version)
                .font(.caption2)
                .foregroundStyle(Brand.mintLight.opacity(0.72))
        }
    }

    private var powerArea: some View {
        VStack(spacing: 15) {
            Button {
                Task { await model.toggleVPN() }
            } label: {
                Text(model.vpn.isConnectedOrConnecting ? "Отключить" : "Подключиться")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(model.vpn.isConnectedOrConnecting ? Brand.navy : .white)
                    .frame(width: 174, height: 174)
                    .background(model.vpn.isConnectedOrConnecting ? Brand.mint : Brand.graphite)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Brand.mint.opacity(0.55), lineWidth: 2))
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 7)
            }
            .buttonStyle(.plain)
            .disabled(!model.vpn.canToggle)
            Text(model.vpn.detail)
                .font(.subheadline)
                .foregroundStyle(Brand.softGray)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private var proxyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Прокси")
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.mintLight)

            Menu {
                Button {
                    model.selectAuto()
                } label: {
                    Label("Авто", systemImage: model.automaticSelection ? "checkmark.circle.fill" : "circle")
                }
                ForEach(model.profiles) { profile in
                    Button {
                        model.select(profile)
                    } label: {
                        let prefix = profile.id == model.primaryProfileID ? "★ " : ""
                        let suffix = model.health[profile.id].map { " · \($0.label)" } ?? ""
                        Label(prefix + profile.name + suffix,
                              systemImage: (!model.automaticSelection && model.selectedProfileID == profile.id) ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                HStack {
                    Text(model.selectedLabel)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Brand.mint)
                }
                .padding(.horizontal, 15)
                .frame(height: 54)
                .background(Brand.navy)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.softGray.opacity(0.45)))
            }

            HStack(spacing: 8) {
                cardButton("＋ Новый", filled: true) { showNewProfile = true }
                cardButton("Изменить", filled: false) {
                    editorProfile = model.profiles.first { $0.id == model.selectedProfileID }
                        ?? model.profiles.first
                }
                .disabled(model.profiles.isEmpty)
            }

            HStack(spacing: 8) {
                cardButton(model.exclusions.isEmpty ? "Исключения" : "Исключения · \(model.exclusions.count)", filled: false) {
                    showExclusions = true
                }
                cardButton("Журнал", filled: false) {
                    model.refreshEvents()
                    showJournal = true
                }
            }

            if !model.profiles.isEmpty {
                Menu {
                    Section("Основной прокси") {
                        ForEach(model.profiles) { profile in
                            Button {
                                model.setPrimary(profile)
                            } label: {
                                Label(profile.name,
                                      systemImage: profile.id == model.primaryProfileID ? "star.fill" : "star")
                            }
                        }
                    }
                    Button {
                        model.setReturnToPrimary(!model.returnToPrimary)
                    } label: {
                        Label(
                            "Возвращать основной после восстановления",
                            systemImage: model.returnToPrimary ? "checkmark.square.fill" : "square"
                        )
                    }
                } label: {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Настройки Auto")
                        Spacer()
                        if model.returnToPrimary {
                            Text("возврат включён").font(.caption)
                        }
                    }
                    .foregroundStyle(Brand.mintLight)
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(16)
        .background(Brand.graphite)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }

    private func cardButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(filled ? Brand.navy : Brand.mintLight)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(filled ? Brand.mint : Brand.navy)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.mint.opacity(filled ? 0 : 0.6)))
    }
}

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
        NavigationStack {
            Form {
                Section("Прокси") {
                    TextField("Название", text: $name)
                    TextField("Хост", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Порт", text: $port)
                        .keyboardType(.numberPad)
                    Picker("Тип", selection: $type) {
                        ForEach(ProxyType.allCases) { type in Text(type.label).tag(type) }
                    }
                }
                Section("Авторизация") {
                    TextField("Логин", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(profile == nil ? "Пароль" : "Пароль (пусто = оставить прежний)", text: $password)
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
            .navigationTitle(profile == nil ? "Новый прокси" : "Изменить прокси")
            .navigationBarTitleDisplayMode(.inline)
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

struct ExclusionsView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [String] = []
    @State private var input = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Введите сайт и нажмите «Добавить». Каждый сайт появится отдельной строкой. Можно вставить URL, host:port или IP.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("example.com", text: $input)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Добавить") { addEntry() }
                    }
                    if let localError {
                        Text(localError).font(.caption).foregroundStyle(.red)
                    }
                }
                Section(entries.isEmpty ? "Список пока пуст" : "Исключения") {
                    ForEach(entries, id: \.self) { host in
                        Text(host)
                    }
                    .onDelete { entries.remove(atOffsets: $0) }
                }
            }
            .navigationTitle("Исключения")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { entries = model.exclusions }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addEntry() }
                        guard localError == nil else { return }
                        Task {
                            if await model.saveExclusions(entries) { dismiss() }
                        }
                    }
                }
            }
        }
    }

    private func addEntry() {
        do {
            if let value = try SiteExclusionPolicy.normalize(input) {
                if !entries.contains(value) { entries.append(value); entries.sort() }
            }
            input = ""
            localError = nil
        } catch {
            localError = error.localizedDescription
        }
    }
}

struct JournalView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.events.isEmpty {
                    Text("Событий пока нет").foregroundStyle(.secondary)
                } else {
                    ForEach(model.events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.type).font(.headline)
                                Spacer()
                                Text(event.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
                            }
                            if let name = event.profileName { Text(name).font(.subheadline) }
                            if let detail = event.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("Журнал")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }
}
