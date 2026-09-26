import SwiftUI
import NetworkExtension

private enum Brand {
    static let navy = Color(red: 0, green: 20/255, blue: 50/255)
    static let mint = Color(red: 0, green: 200/255, blue: 160/255)
    static let mintLight = Color(red: 120/255, green: 250/255, blue: 230/255)
    static let softGray = Color(red: 200/255, green: 210/255, blue: 220/255)
    static let graphite = Color(red: 40/255, green: 50/255, blue: 70/255)
    static let surface = Color(red: 16/255, green: 40/255, blue: 70/255)
}

private enum AppDestination: String, CaseIterable, Identifiable {
    case home
    case profiles
    case activity
    case settings

    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Главная"
        case .profiles: return "Профили"
        case .activity: return "Активность"
        case .settings: return "Настройки"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .profiles: return "rectangle.stack"
        case .activity: return "waveform.path.ecg"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var destination: AppDestination = .home
    @State private var editorProfile: ProxyProfile?
    @State private var showNewProfile = false
    @State private var showExclusions = false
    @State private var showAppExclusions = false

    var body: some View {
        Group {
#if targetEnvironment(macCatalyst)
            desktopShell
#else
            mobileShell
#endif
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
        .sheet(isPresented: $showAppExclusions) {
            ApplicationExclusionsView()
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

    private var mobileShell: some View {
        TabView(selection: $destination) {
            homeScreen
                .tag(AppDestination.home)
                .tabItem { Label(AppDestination.home.title, systemImage: AppDestination.home.icon) }
            profilesScreen
                .tag(AppDestination.profiles)
                .tabItem { Label(AppDestination.profiles.title, systemImage: AppDestination.profiles.icon) }
            activityScreen
                .tag(AppDestination.activity)
                .tabItem { Label(AppDestination.activity.title, systemImage: AppDestination.activity.icon) }
            settingsScreen
                .tag(AppDestination.settings)
                .tabItem { Label(AppDestination.settings.title, systemImage: AppDestination.settings.icon) }
        }
        .tint(Brand.mint)
    }

#if targetEnvironment(macCatalyst)
    private var desktopShell: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header
                    .padding(.bottom, 12)
                ForEach(AppDestination.allCases) { item in
                    Button {
                        destination = item
                        if item == .activity { model.refreshEvents() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon).frame(width: 22)
                            Text(item.title).fontWeight(.semibold)
                            Spacer()
                        }
                        .foregroundStyle(destination == item ? Brand.navy : Brand.mintLight)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(destination == item ? Brand.mint : Brand.graphite)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("v\(AppShared.version)")
                    .font(.caption)
                    .foregroundStyle(Brand.softGray.opacity(0.72))
            }
            .padding(18)
            .frame(width: 208)
            .background(Brand.navy)

            Divider().overlay(Brand.softGray.opacity(0.22))

            Group {
                switch destination {
                case .home: homeScreen
                case .profiles: profilesScreen
                case .activity: activityScreen
                case .settings: settingsScreen
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Brand.navy)
    }
#endif

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image("ArvectumWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 24)
                .accessibilityLabel("Arvectum")
            Text("Proxy Launcher")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Brand.mint)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 4)
#if !targetEnvironment(macCatalyst)
            Text(AppShared.version)
                .font(.caption2)
                .foregroundStyle(Brand.mintLight.opacity(0.72))
#endif
        }
    }

    private var homeScreen: some View {
        ZStack {
            Brand.navy.ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 18) {
#if !targetEnvironment(macCatalyst)
                        header
#endif
                        if geometry.size.width >= 700 {
                            HStack(alignment: .top, spacing: 18) {
                                connectionCard.frame(maxWidth: .infinity)
                                activeProfileCard.frame(maxWidth: .infinity)
                            }
                        } else {
                            connectionCard
                            activeProfileCard
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    private var connectionCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Соединение")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.mintLight)
                Spacer()
                Text(model.vpn.detail)
                    .font(.caption)
                    .foregroundStyle(connectionStatusColor)
            }
            Button {
                Task { await model.toggleVPN() }
            } label: {
                Text(primaryActionTitle)
                    .font(.system(size: powerDiameter < 140 ? 17 : 20, weight: .bold))
                    .foregroundStyle(model.vpn.isConnectedOrConnecting ? Brand.navy : .white)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .frame(width: powerDiameter, height: powerDiameter)
                    .background(model.vpn.isConnectedOrConnecting ? Brand.mint : Brand.graphite)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Brand.mint.opacity(0.58), lineWidth: 2))
                    .shadow(color: .black.opacity(0.24), radius: 10, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(!model.vpn.canToggle)
            Text(connectionHelp)
                .font(.footnote)
                .foregroundStyle(Brand.softGray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Brand.graphite)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var activeProfileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Активный профиль")
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.mintLight)
            Text(model.selectedLabel)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(model.automaticSelection ? "APL выбирает доступный профиль автоматически." : "Выбран вручную.")
                .font(.footnote)
                .foregroundStyle(Brand.softGray)
            Menu {
                profileSelectionMenu
            } label: {
                HStack {
                    Text("Выбрать профиль")
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.navy)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Brand.mint)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Button {
                destination = .profiles
            } label: {
                Label("Управление профилями", systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryBrandButtonStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var profilesScreen: some View {
        ZStack {
            Brand.navy.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
#if !targetEnvironment(macCatalyst)
                    header
#endif
                    sectionTitle("Профили", subtitle: "Выбор, добавление и приоритет прокси")
                    Menu { profileSelectionMenu } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Текущий профиль").font(.caption).foregroundStyle(Brand.softGray)
                                Text(model.selectedLabel).font(.headline).foregroundStyle(.white).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.down").foregroundStyle(Brand.mint)
                        }
                        .padding(16)
                        .background(Brand.graphite)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    HStack(spacing: 10) {
                        cardButton("＋ Новый", filled: true) { showNewProfile = true }
                        cardButton("Изменить", filled: false) {
                            editorProfile = model.profiles.first { $0.id == model.selectedProfileID }
                                ?? model.profiles.first
                        }
                        .disabled(model.profiles.isEmpty)
                    }
                    if !model.profiles.isEmpty {
                        autoSettingsCard
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var activityScreen: some View {
        ZStack {
            Brand.navy.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
#if !targetEnvironment(macCatalyst)
                    header
#endif
                    sectionTitle("Активность", subtitle: "Состояние соединения и последние события")
                    HStack {
                        Label(model.vpn.detail, systemImage: "bolt.horizontal.circle")
                            .foregroundStyle(connectionStatusColor)
                        Spacer()
                        Button("Обновить") { model.refreshEvents() }
                            .foregroundStyle(Brand.mint)
                    }
                    .padding(16)
                    .background(Brand.graphite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    if model.events.isEmpty {
                        Text("Событий пока нет")
                            .foregroundStyle(Brand.softGray)
                            .padding(16)
                    } else {
                        ForEach(model.events) { event in
                            eventRow(event)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { model.refreshEvents() }
    }

    private var settingsScreen: some View {
        ZStack {
            Brand.navy.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
#if !targetEnvironment(macCatalyst)
                    header
#endif
                    sectionTitle("Настройки", subtitle: "Маршрутизация и поведение APL")
                    settingsButton("Исключения сайтов", icon: "globe") { showExclusions = true }
                    settingsButton("Исключения приложений", icon: "app.badge") { showAppExclusions = true }
                    if !model.profiles.isEmpty {
                        autoSettingsCard
                    }
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text(AppShared.version).foregroundStyle(Brand.softGray)
                    }
                    .padding(16)
                    .foregroundStyle(.white)
                    .background(Brand.graphite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var profileSelectionMenu: some View {
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
                      systemImage: (!model.automaticSelection && model.selectedProfileID == profile.id)
                        ? "checkmark.circle.fill" : "circle")
            }
        }
    }

    private var autoSettingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Auto и приоритет")
                .font(.headline)
                .foregroundStyle(.white)
            Menu {
                Section("Приоритетный прокси") {
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
                        "После сбоя возвращаться к приоритетному прокси",
                        systemImage: model.returnToPrimary ? "checkmark.square.fill" : "square"
                    )
                }
            } label: {
                HStack {
                    Text(model.returnToPrimary ? "Возврат к приоритетному включён" : "Оставаться на текущем после сбоя")
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.mintLight)
                .padding(14)
                .background(Brand.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Brand.graphite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func eventRow(_ event: TunnelEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(event.type).font(.headline)
                Spacer()
                Text(event.timestamp, style: .time).font(.caption).foregroundStyle(Brand.softGray)
            }
            if let name = event.profileName { Text(name).font(.subheadline) }
            if let detail = event.detail { Text(detail).font(.caption).foregroundStyle(Brand.softGray) }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Brand.graphite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.weight(.bold)).foregroundStyle(.white)
            Text(subtitle).font(.subheadline).foregroundStyle(Brand.softGray)
        }
    }

    private func settingsButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24)
                Text(title).fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(Brand.graphite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func cardButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(filled ? Brand.navy : Brand.mintLight)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(filled ? Brand.mint : Brand.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.mint.opacity(filled ? 0 : 0.6)))
    }

    private var primaryActionTitle: String {
        switch model.vpn.status {
        case .connected, .reasserting: return "Отключить"
        case .connecting: return "Подключение…"
        case .disconnecting: return "Отключение…"
        default: return "Подключиться"
        }
    }

    private var connectionHelp: String {
        switch model.vpn.status {
        case .connected: return "Трафик устройства направляется через выбранный прокси."
        case .connecting, .reasserting: return "APL устанавливает защищённый системный туннель."
        case .disconnecting: return "APL возвращает обычное сетевое подключение."
        default: return "Нажмите, чтобы направить трафик через APL."
        }
    }

    private var connectionStatusColor: Color {
        switch model.vpn.status {
        case .connected: return Brand.mintLight
        case .connecting, .reasserting: return Brand.mint
        default: return Brand.softGray
        }
    }

    private var powerDiameter: CGFloat {
#if targetEnvironment(macCatalyst)
        return 116
#else
        return 164
#endif
    }
}

private struct SecondaryBrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.mintLight)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Brand.navy.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.mint.opacity(0.55)))
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
        NavigationView {
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
            .navigationTitle("Исключения сайтов")
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


struct ApplicationExclusionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: IOSAppRoutingMode = .normallyOn
    @State private var storageError: String?

    var body: some View {
        NavigationView {
            List {
                Section("Обычное состояние") {
                    Picker("Режим", selection: $mode) {
                        ForEach(IOSAppRoutingMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                    .onChange(of: mode) { newValue in
                        saveAndApplyMode(newValue)
                    }
                }

                Section("Что произойдёт") {
                    Text(modeExplanation).font(.footnote)
                    Label("После первоначальной настройки режим меняется здесь, в APL. Системные автоматизации переделывать не нужно.", systemImage: "checkmark.circle")
                        .font(.footnote)
                }

                Section("Один раз настроить iPhone") {
                    Link(destination: URL(string: "shortcuts://create-shortcut")!) {
                        Label("Продолжить в «Командах»", systemImage: "arrow.up.forward.app")
                    }
                    Text("1. «Приложение → Открыто»: выберите нужные приложения и действие APL «Приложение открыто».")
                        .font(.footnote)
                    Text("2. «Приложение → Закрыто»: тот же список и действие APL «Приложение закрыто».")
                        .font(.footnote)
                    Text("Для обеих выберите запуск «Немедленно». После этого APL сам решает, включать или выключать прокси.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Ограничение iOS") {
                    Text("Apple не предоставляет приложению публичный API для создания или изменения системного триггера «Приложение открыто/закрыто». Поэтому список приложений выбирается в «Командах». Сам режим работы хранится в APL.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let storageError {
                    Section { Text(storageError).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Автоматизация приложений")
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
            return "APL включён для всего устройства. Открыли выбранное приложение — APL временно выключился. Вышли — включился обратно."
        case .normallyOff:
            return "APL выключен, устройство работает напрямую. Открыли выбранное приложение — APL временно включился. Вышли — выключился обратно."
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
}

struct JournalView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
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
