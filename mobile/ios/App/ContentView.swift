import SwiftUI
import NetworkExtension
import UIKit
import WebKit

/// Semantic iPhone appearance colors that follow dynamic device traits.
enum Brand {
    static let navy = Color(red: 0, green: 20/255, blue: 50/255)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let canvas = adaptive(
        light: UIColor(red: 0.957, green: 0.973, blue: 0.988, alpha: 1),
        dark: UIColor(red: 0, green: 20/255, blue: 50/255, alpha: 1)
    )
    static let graphite = adaptive(
        light: .white,
        dark: UIColor(red: 40/255, green: 50/255, blue: 70/255, alpha: 1)
    )
    static let surface = adaptive(
        light: UIColor(red: 0.918, green: 0.949, blue: 0.970, alpha: 1),
        dark: UIColor(red: 16/255, green: 40/255, blue: 70/255, alpha: 1)
    )
    static let text = adaptive(
        light: UIColor(red: 0.075, green: 0.133, blue: 0.220, alpha: 1),
        dark: .white
    )
    static let softGray = adaptive(
        light: UIColor(red: 0.290, green: 0.344, blue: 0.410, alpha: 1),
        dark: UIColor(red: 200/255, green: 210/255, blue: 220/255, alpha: 1)
    )
    static let mint = adaptive(
        light: UIColor(red: 0, green: 0.43, blue: 0.34, alpha: 1),
        dark: UIColor(red: 0, green: 200/255, blue: 160/255, alpha: 1)
    )
    static let mintLight = adaptive(
        light: UIColor(red: 0.008, green: 0.40, blue: 0.36, alpha: 1),
        dark: UIColor(red: 120/255, green: 250/255, blue: 230/255, alpha: 1)
    )
    static let actionText = adaptive(
        light: .white,
        dark: UIColor(red: 0, green: 20/255, blue: 50/255, alpha: 1)
    )
    // The original wordmark has light lettering.
    // Load the bundled PNG explicitly: SwiftUI named-image lookup can fail for
    // a standalone resource PNG not registered in an asset catalog.
    static var wordmark: Image {
        if let path = Bundle.main.path(forResource: "ArvectumWordmark", ofType: "png"),
           let image = UIImage(contentsOfFile: path) {
            return Image(uiImage: image)
        }
        return Image(systemName: "network")
    }
    static let logoBacking = adaptive(
        light: UIColor(red: 0, green: 20/255, blue: 50/255, alpha: 1),
        dark: .clear
    )
}

private enum AppDestination: String, CaseIterable, Identifiable {
    case home
    case profiles
    case activity
    case settings

    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return AppL10n.tr("Главная")
        case .profiles: return AppL10n.tr("Профили")
        case .activity: return AppL10n.tr("Активность")
        case .settings: return AppL10n.tr("Настройки")
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

#if targetEnvironment(macCatalyst)
/// Gives both desktop home cards the height of the taller card at the
/// available column width. Unlike a hard-coded height this also accommodates
/// longer localized copy, font scaling and window resizing.
private struct EqualHeightDashboardLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = max(0, proposal.width ?? 0)
        guard !subviews.isEmpty else { return CGSize(width: width, height: 0) }
        let cardWidth = max(0, (width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count))
        let tallest = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height
        }.max() ?? 0
        return CGSize(width: width, height: tallest)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }
        let cardWidth = max(0, (bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count))
        for (index, card) in subviews.enumerated() {
            card.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * (cardWidth + spacing), y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: cardWidth, height: bounds.height)
            )
        }
    }
}
#endif

private struct ProxyImportRequest: Identifiable {
    let id = UUID()
    let source: String
}

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @AppStorage("appearanceMode.v1") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("appLanguage.v1") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("setupGuideSeen.v1") private var setupGuideSeen = false
    @State private var showSetupGuide = false
    @State private var openProfileAfterGuide = false
    @State private var destination: AppDestination = .home
    @State private var editorProfile: ProxyProfile?
    @State private var showNewProfile = false
    @State private var importRequest: ProxyImportRequest?
    @State private var showExclusions = false
    @State private var showQuickActions = false
    @State private var showAppExclusions = false

    var body: some View {
        Group {
#if targetEnvironment(macCatalyst)
            desktopShell
#else
            mobileShell
#endif
        }
        .task {
            await model.prepare()
#if !targetEnvironment(macCatalyst)
            if !setupGuideSeen && model.profiles.isEmpty {
                showSetupGuide = true
            }
#endif
        }
        .sheet(isPresented: $showSetupGuide, onDismiss: {
            if openProfileAfterGuide {
                openProfileAfterGuide = false
                showNewProfile = true
            }
        }) {
            SetupGuideView(
                onClose: {
                    setupGuideSeen = true
                    showSetupGuide = false
                },
                onCreateProfile: {
                    setupGuideSeen = true
                    openProfileAfterGuide = true
                    showSetupGuide = false
                }
            )
        }
        .sheet(isPresented: $showNewProfile) {
            ProfileEditorView(profile: nil).environmentObject(model)
        }
        .sheet(item: $importRequest) { request in
            ProxyImportView(initialSource: request.source).environmentObject(model)
        }
        .sheet(item: $editorProfile) { profile in
            ProfileEditorView(profile: profile).environmentObject(model)
        }
        .onOpenURL { url in
            do {
                importRequest = ProxyImportRequest(source: try ProxyImport.fromDeepLink(url))
            } catch { model.errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $showQuickActions) {
            QuickActionsHelpView()
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
            Text(AppL10n.tr(model.errorMessage ?? ""))
        }
    }

    private var mobileShell: some View {
        VStack(spacing: 0) {
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
            // A sibling rather than an inset on TabView. The actual ad SDK's
            // sticky height is measured by the stack; it must not displace
            // or obscure the native tab bar on compact iPhones.
            SettingsBannerView()
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(Brand.canvas)
        }
        .background(Brand.canvas)
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
                            Text(item.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(destination == item ? Brand.actionText : Brand.mintLight)
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
            .background(Brand.canvas)

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
        .frame(minWidth: 760, minHeight: 440)
        .background(Brand.canvas)
    }
#endif

    private var header: some View {
#if targetEnvironment(macCatalyst)
        VStack(alignment: .leading, spacing: 5) {
            Brand.wordmark
                .resizable()
                .scaledToFit()
                .frame(width: 144, height: 28, alignment: .leading)
                .padding(6)
                .background(Brand.logoBacking, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Arvectum")
            Text("Proxy Launcher")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Brand.mint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
#else
        HStack(alignment: .center, spacing: 8) {
            Brand.wordmark
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 24)
                .padding(6)
                .background(Brand.logoBacking, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Arvectum")
            Text("Proxy Launcher")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Brand.mint)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 4)
            Text(AppShared.version)
                .font(.caption2)
                .foregroundStyle(Brand.mintLight.opacity(0.72))
        }
#endif
    }

    // Home must remain fully visible; the large banner test is enabled only
    // via Simulator launch arguments, never as a fake production ad.
    private var bannerPreview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-aplHomeBannerQA")
#else
        false
#endif
    }

    private var bannerHeightQA: CGFloat {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-aplHomeBannerTallQA") ? 100 : 90
#else
        90
#endif
    }

    private var qaProfile: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-aplHomeProfileQA")
#else
        false
#endif
    }
    private var qaState: String? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-aplHomeStatusQA"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
#else
        return nil
#endif
    }
    private var qaStatusTitle: String {
        switch qaState {
        case "connected": return "Подключено"
        case "connecting": return "Подключение…"
        case "disconnecting": return "Отключение…"
        default: return model.vpn.detail
        }
    }
    private var qaActionTitle: String {
        switch qaState {
        case "connected": return "Отключить"
        case "connecting": return "Подключение…"
        case "disconnecting": return "Отключение…"
        default: return primaryActionTitle
        }
    }
    private var qaHelp: String {
        switch qaState {
        case "connected": return "Трафик устройства направляется через выбранный прокси."
        case "connecting": return "APL устанавливает защищённый системный туннель."
        case "disconnecting": return "APL возвращает обычное сетевое подключение."
        default: return connectionHelp
        }
    }

    private var homeScreen: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()
            GeometryReader { geometry in
#if targetEnvironment(macCatalyst)
                ScrollView {
                    VStack(spacing: 18) {
                        if geometry.size.width >= 820 {
                            EqualHeightDashboardLayout(spacing: 18) {
                                connectionCard(compact: false)
                                activeProfileCard(compact: false)
                            }
                        } else {
                            connectionCard(compact: false)
                            activeProfileCard(compact: false)
                        }
                    }.padding(18).frame(maxWidth: 920).frame(maxWidth: .infinity)
                }
#else
                let tight = geometry.size.height < 510
                let compact = geometry.size.height < 680
                let gap: CGFloat = tight ? 6 : (compact ? 9 : 14)
                VStack(spacing: gap) {
                    header.homeMeasured("header")
                    if geometry.size.width >= 700 {
                        HStack(alignment: .top, spacing: gap) {
                            connectionCard(compact: compact)
                            activeProfileCard(compact: compact)
                        }
                    } else {
                        connectionCard(compact: compact).homeMeasured("connection")
                        activeProfileCard(compact: compact).homeMeasured("profile")
                    }
                    Spacer(minLength: 0)
                    if bannerPreview {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Brand.surface)
                            .overlay {
                                Label("\(Int(bannerHeightQA)) pt banner layout QA", systemImage: "rectangle.on.rectangle")
                                    .font(.caption2).foregroundStyle(Brand.softGray)
                            }
                            .frame(height: tight ? 60 : bannerHeightQA)
                            .homeMeasured("banner")
                    }
                }
                .padding(.horizontal, compact ? 12 : 18)
                .padding(.vertical, tight ? 6 : (compact ? 9 : 14))
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .coordinateSpace(name: "APLHome")
                .homeMeasured("viewport")
                .onPreferenceChange(HomeFramePreference.self) { frames in
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-aplHomeLayoutProbe") {
                        HomeLayoutProbe.save(frames, language: AppL10n.effectiveLanguage,
                            width: geometry.size.width, height: geometry.size.height)
                    }
#endif
                }
#endif
            }
        }
    }
    // Preserve equal-height macOS Catalyst cards while iPhone Home measures
    // intrinsic card heights to leave space for the bottom banner footprint.
    private var dashboardCardMaxHeight: CGFloat? {
#if targetEnvironment(macCatalyst)
        .infinity
#else
        nil
#endif
    }

    private func connectionCard(compact: Bool) -> some View {
        VStack(spacing: compact ? 9 : 18) {
            HStack(spacing: compact ? 5 : 10) {
                Text(AppL10n.tr("Соединение"))
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Brand.text)
                Spacer(minLength: 3)
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 9))
                        .accessibilityHidden(true)
                    Text(AppL10n.tr(qaStatusTitle))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                .foregroundStyle(connectionStatusColor)
                .padding(.horizontal, compact ? 8 : 12)
                .padding(.vertical, compact ? 5 : 8)
                .background(Brand.canvas.opacity(0.7))
                .clipShape(Capsule())
                .accessibilityElement(children: .combine)
            }
            Button {
                if model.profiles.isEmpty && !model.vpn.isConnectedOrConnecting {
                    showNewProfile = true
                } else {
                    Task { await model.toggleVPN() }
                }
            } label: {
                HStack(spacing: compact ? 8 : 14) {
                    Image(systemName: model.profiles.isEmpty && !model.vpn.isConnectedOrConnecting
                        ? "plus.circle.fill" : "power")
                        .font(.system(size: compact ? 20 : 25, weight: .bold))
                        .accessibilityHidden(true)
                    Text(AppL10n.tr(qaActionTitle))
                        .font(.system(size: compact ? 18 : 22, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Spacer(minLength: 0)
                    Image(systemName: model.vpn.isConnectedOrConnecting ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.system(size: compact ? 19 : 24, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, compact ? 12 : 22)
                .foregroundStyle(Brand.actionText)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 56 : 76)
                .background(Brand.mint)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Brand.mintLight.opacity(0.7), lineWidth: 2)
                )
                .shadow(color: Brand.mint.opacity(0.19), radius: 14, y: 6)
                .opacity(model.vpn.canToggle ? 1 : 0.6)
            }
            .buttonStyle(.plain)
            .disabled(!model.vpn.canToggle)
            .homeMeasured("primaryAction")
            .accessibilityLabel(AppL10n.tr(qaActionTitle))
            .accessibilityHint(model.profiles.isEmpty && !model.vpn.isConnectedOrConnecting
                ? "Открыть создание первого прокси"
                : model.vpn.isConnectedOrConnecting
                    ? "Отключить системный прокси-туннель"
                    : "Подключиться через выбранный прокси")
            Text(AppL10n.tr(qaHelp))
                .font(compact ? .caption : .footnote)
                .foregroundStyle(Brand.softGray)
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 2 : 3)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
        }
        .padding(compact ? 11 : 18)
        .frame(maxWidth: .infinity, maxHeight: dashboardCardMaxHeight, alignment: .top)
        .background(Brand.graphite)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func activeProfileCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 12) {
            Text(AppL10n.tr("Выбор прокси"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Brand.mintLight)
            Text(model.profiles.isEmpty && !qaProfile ? AppL10n.tr("Прокси пока нет") : (qaProfile ? "QA Proxy" : model.selectedLabel))
                .font(compact ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(Brand.text)
                .lineLimit(1)
            if (!model.profiles.isEmpty || qaProfile) && !compact {
                Text(AppL10n.tr(model.automaticSelection ? "APL выбирает доступный профиль автоматически." : "Используется выбранный профиль."))
                    .font(compact ? .caption : .footnote)
                    .foregroundStyle(Brand.softGray)
            }
            if model.profiles.isEmpty && !qaProfile {
                Text(AppL10n.tr("Добавьте первый прокси, чтобы начать. Понадобятся адрес и порт."))
                    .font(compact ? .caption : .footnote)
                    .foregroundStyle(Brand.softGray)
                    .lineLimit(compact ? 2 : 3)
                    .minimumScaleFactor(0.68)
                if !compact {
                Button {
                    showNewProfile = true
                } label: {
                    Label("Добавить прокси", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryBrandButtonStyle())
                }
            } else {
                Menu {
                    profileSelectionMenu
                } label: {
                    HStack {
                        Text(AppL10n.tr("Выбрать профиль"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.actionText)
                    .padding(.horizontal, 14)
                    .frame(height: compact ? 44 : 52)
                    .background(Brand.mint)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if !compact {
                Button {
                    destination = .profiles
                } label: {
                    Label("Управление профилями", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryBrandButtonStyle())
                }
            }
        }
        .padding(compact ? 9 : 18)
        .frame(maxWidth: .infinity, maxHeight: dashboardCardMaxHeight, alignment: .topLeading)
        .background(Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var profilesScreen: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
#if !targetEnvironment(macCatalyst)
                    header
#endif
                    sectionTitle("Профили", subtitle: "Выбор, добавление и приоритет прокси")
                    if !model.profiles.isEmpty {
                    Menu { profileSelectionMenu } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Текущий профиль").font(.caption).foregroundStyle(Brand.softGray)
                                Text(AppL10n.tr(model.selectedLabel)).font(.headline).foregroundStyle(Brand.text).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.down").foregroundStyle(Brand.mint)
                        }
                        .padding(16)
                        .background(Brand.graphite)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    }
                    HStack(spacing: 10) {
                        cardButton(model.profiles.isEmpty ? "＋ Добавить первый прокси" : "＋ Новый", filled: true) { showNewProfile = true }
                        cardButton("Импортировать прокси", filled: false) { importRequest = ProxyImportRequest(source: "") }
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
            Brand.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
#if !targetEnvironment(macCatalyst)
                    header
#endif
                    sectionTitle("Активность", subtitle: "Состояние соединения и последние события")
                    HStack {
                        Label(AppL10n.tr(model.vpn.detail), systemImage: "bolt.horizontal.circle")
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
            Brand.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
#if !targetEnvironment(macCatalyst)
                    header
#endif
                    sectionTitle("Настройки", subtitle: "Маршрутизация и поведение APL")
#if !targetEnvironment(macCatalyst)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Оформление", systemImage: "paintpalette")
                            .font(.headline)
                            .foregroundStyle(Brand.text)
                        Picker("Тема оформления", selection: $appearanceMode) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityHint("Как в системе, светлая или тёмная тема")
                        Text("Системная тема автоматически следует настройкам iPhone.")
                            .font(.footnote)
                            .foregroundStyle(Brand.softGray)
                    }
                    .padding(16)
                    .background(Brand.graphite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
#endif
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Язык приложения", systemImage: "character.bubble")
                            .font(.headline)
                            .foregroundStyle(Brand.text)
                        Picker("Язык приложения", selection: $appLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.title).tag(language.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("Выберите язык интерфейса или используйте язык iPhone.")
                            .font(.footnote)
                            .foregroundStyle(Brand.softGray)
                    }
                    .padding(16)
                    .background(Brand.graphite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    settingsButton("Первое подключение", icon: "questionmark.circle") {
                        showSetupGuide = true
                    }
                    settingsButton("Исключения сайтов", icon: "globe") { showExclusions = true }
                    if #available(iOS 16.0, *) {
                        settingsButton(QuickActionsCopy.text("Быстрые команды VPN", en: "VPN quick actions"),
                                       icon: "bolt.circle") { showQuickActions = true }
                            .accessibilityIdentifier("settings.quickActions")
                    }
#if !targetEnvironment(macCatalyst)
                    settingsButton("Автоматизация приложений", icon: "app.badge") { showAppExclusions = true }
#endif
                    if !model.profiles.isEmpty {
                        autoSettingsCard
                    }
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text(AppShared.version).foregroundStyle(Brand.softGray)
                    }
                    .padding(16)
                    .foregroundStyle(Brand.text)
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
                .foregroundStyle(Brand.text)
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
                    Text(AppL10n.tr(model.returnToPrimary ? "Возврат к приоритетному включён" : "Оставаться на текущем после сбоя"))
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
                Text(AppL10n.tr(event.type)).font(.headline)
                Spacer()
                Text(event.timestamp, style: .time).font(.caption).foregroundStyle(Brand.softGray)
            }
            if let name = event.profileName { Text(name).font(.subheadline) }
            if let detail = event.detail { Text(detail).font(.caption).foregroundStyle(Brand.softGray) }
        }
        .foregroundStyle(Brand.text)
        .padding(14)
        .background(Brand.graphite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppL10n.tr(title)).font(.title2.weight(.bold)).foregroundStyle(Brand.text)
            Text(AppL10n.tr(subtitle)).font(.subheadline).foregroundStyle(Brand.softGray)
        }
    }

    private func settingsButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24)
                Text(AppL10n.tr(title)).fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(Brand.text)
            .padding(16)
            .background(Brand.graphite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func cardButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(AppL10n.tr(title), action: action)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(filled ? Brand.actionText : Brand.mintLight)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(filled ? Brand.mint : Brand.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.mint.opacity(filled ? 0 : 0.6)))
    }

    private var primaryActionTitle: String {
        if model.profiles.isEmpty && !model.vpn.isConnectedOrConnecting {
            return "Добавить прокси"
        }
        switch model.vpn.status {
        case .connected, .reasserting: return "Отключить"
        case .connecting: return "Подключение…"
        case .disconnecting: return "Отключение…"
        default: return "Подключиться"
        }
    }

    private var connectionHelp: String {
        if model.profiles.isEmpty && !model.vpn.isConnectedOrConnecting {
            return "Без профиля подключение невозможно. Добавьте прокси для начала работы."
        }
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

}

private struct PrimaryBrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Brand.actionText)
            .frame(height: 52)
            .background(Brand.mint.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SecondaryBrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.mintLight)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Brand.canvas.opacity(configuration.isPressed ? 0.72 : 1))
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
                    Text("Данные подключения выдаёт поставщик прокси или администратор сети.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Название", text: $name)
                    TextField("Хост", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Порт", text: $port)
                        .keyboardType(.numberPad)
                    Picker("Тип", selection: $type) {
                        ForEach(ProxyType.allCases) { type in Text(AppL10n.tr(type.label)).tag(type) }
                    }
                    Text("Хост — адрес сервера, порт — его номер. Тип уточните у поставщика.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Авторизация") {
                    Text("Логин и пароль нужны только для прокси с авторизацией.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            .navigationTitle(AppL10n.tr(profile == nil ? "Новый прокси" : "Изменить прокси"))
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

private struct ScaledEmptyStatus: UIViewRepresentable {
    var text: String
    func makeUIView(context: Context) -> UILabel {
        let view = UILabel()
        view.numberOfLines = 0
        view.adjustsFontForContentSizeCategory = true
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.textColor = .label
        return view
    }
    func updateUIView(_ view: UILabel, context: Context) {
        view.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection)
        view.text = text
        view.accessibilityLabel = text
        view.invalidateIntrinsicContentSize()
    }
}

struct ExclusionsView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [String] = []
    @State private var graph = SmartExclusionGraph()
    @State private var scannedParent = ""
    @State private var externalHints: [String] = []
    @State private var pendingExternalHost: String?
    @State private var confirmExternal = false
    @State private var undoEntries: [String]?
    @State private var undoGraph: SmartExclusionGraph?
    @Environment(\.dynamicTypeSize) private var textSize
    @FocusState private var isDomainFocused: Bool
    @State private var input = ""
    @State private var localError: String?
    @State private var confirmClearAll = false
    @State private var saving = false
    @State private var discovered: [String] = []
    @State private var selectedDiscovered: Set<String> = []
    @State private var scanning = false
    @State private var scanner: ExclusionWebScanner?

    var body: some View {
        NavigationView {
            List {
                editorSection
                if !discovered.isEmpty {
                    Section(SmartExclusionsUX.text("Найденные домены — выберите для исключения")) {
                        ForEach(discovered, id: \.self) { host in
                            Button {
                                if !selectedDiscovered.insert(host).inserted { selectedDiscovered.remove(host) }
                            } label: {
                                HStack {
                                    Text(host).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: selectedDiscovered.contains(host) ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                        Button(SmartExclusionsUX.text("Подтвердить выбранные для обхода")) {
                            do {
                                snapshotUndo()
                                var next = graph
                                for child in selectedDiscovered {
                                    try next.set(.approved, parent: scannedParent, child: child)
                                }
                                let manual = try SiteExclusionPolicy.normalizeAll(entries + [scannedParent])
                                _ = try next.effective(manual: manual)
                                graph = next
                                entries = manual
                                discovered = []
                                selectedDiscovered = []
                                localError = nil
                            } catch { localError = error.localizedDescription }
                        }.disabled(selectedDiscovered.isEmpty)
                    }
                }
                if !externalHints.isEmpty {
                    Section {
                        ForEach(externalHints, id: \.self) { host in
                            HStack {
                                Text(host).textSelection(.enabled)
                                Spacer()
                                Button(SmartExclusionsUX.text("Добавить вручную")) {
                                    pendingExternalHost = host
                                    confirmExternal = true
                                }
                                .buttonStyle(.borderless)
                                .frame(minHeight: 44)
                                .accessibilityLabel(SmartExclusionsUX.text("Добавить вручную") + " " + host)
                            }
                        }
                    } header: {
                        Text(SmartExclusionsUX.text("Сторонние ресурсы — только вручную"))
                    } footer: {
                        Text(SmartExclusionsUX.text("Сторонние домены могут обслуживать рекламу или использовать общие IP-адреса. Добавление вручную направит все соединения к этим IP мимо VPN. Без явного подтверждения правила не меняются."))
                    }
                }
                if !graph.edges.isEmpty {
                    Section {
                        ForEach(Array(Set(graph.edges.map(\.parent))).sorted(), id: \.self) { parent in
                            DisclosureGroup(parent) {
                                ForEach(graph.edges.filter { $0.parent == parent }) { edge in
                                    graphEdgeRow(edge, parent: parent)
                                }
                                Button(SmartExclusionsUX.text("Удалить связи сайта"), role: .destructive) {
                                    snapshotUndo()
                                    graph.remove(parent: parent)
                                }
                            }
                        }
                    } header: {
                        Text(SmartExclusionsUX.text("Связанные домены (требуют подтверждения)"))
                    } footer: {
                        Text(SmartExclusionsUX.text("Связи хранятся локально 7 дней. Повторный анализ обновляет дату наблюдения, но не меняет ваше решение. Сторонние CDN не обходятся автоматически."))
                    }
                }
                if undoEntries != nil {
                    Section {
                        Button(SmartExclusionsUX.text("Отменить последнее изменение")) { restoreUndo() }
                    }
                }
                Section {
                    if entries.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "tray")
                                .accessibilityHidden(true)
                            ScaledEmptyStatus(text: AppL10n.tr("Список пока пуст"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                    }
                    ForEach(entries, id: \.self) { host in
                        HStack(spacing: 12) {
                            Text(host)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if host.contains(".") && !host.contains(":") {
                                Button { scanSite(host) } label: {
                                    Image(systemName: "magnifyingglass")
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .disabled(scanning)
                                .buttonStyle(.borderless)
                                .accessibilityLabel(SmartExclusionsUX.text("Найти связанные домены для ") + host)
                            }
                            Button(role: .destructive) {
                                snapshotUndo()
                                entries.removeAll { $0 == host }
                                graph.remove(parent: host)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                    .frame(minWidth: 36, minHeight: 36)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(AppL10n.tr("Удалить исключение") + " \(host)")
                        }
                    }
                    .onDelete { offsets in
                        snapshotUndo()
                        let removed = offsets.map { entries[$0] }
                        entries.remove(atOffsets: offsets)
                        for host in removed { graph.remove(parent: host) }
                    }
                } header: {
                    if !entries.isEmpty {
                        HStack {
                            Text(AppL10n.tr("Исключения") + " (\(entries.count))")
                                .font(.subheadline)
                            Spacer()
                            Button("Очистить все", role: .destructive) {
                                confirmClearAll = true
                            }
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                            .accessibilityHint("Удалить все исключения после подтверждения")
                        }
                    }
                } footer: {
                    if !entries.isEmpty {
                        Text(SmartExclusionsUX.text("Изменения вступят в силу после сохранения и переподключения VPN."))
                    }
                }
            }
            .navigationTitle("Исключения сайтов")
            .navigationBarTitleDisplayMode(.large)
            .tint(Brand.mint)
            .confirmationDialog(
                "Очистить все исключения?",
                isPresented: $confirmClearAll,
                titleVisibility: .visible
            ) {
                Button("Очистить все", role: .destructive) {
                    snapshotUndo()
                    entries.removeAll()
                    graph = SmartExclusionGraph()
                    discovered = []
                    selectedDiscovered = []
                    externalHints = []
                    input = ""
                    localError = nil
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Все исключения будут удалены из списка. Изменения применятся только после нажатия «Сохранить».")
            }
            .confirmationDialog(SmartExclusionsUX.text("Разрешить прямой доступ для стороннего домена?"),
                                isPresented: $confirmExternal, titleVisibility: .visible) {
                Button(SmartExclusionsUX.text("Добавить вручную")) {
                    guard let host = pendingExternalHost else { return }
                    do {
                        let updated = try SiteExclusionPolicy.normalizeAll(entries + [host])
                        _ = try graph.effective(manual: updated)
                        snapshotUndo()
                        entries = updated
                        externalHints.removeAll { $0 == host }
                        localError = nil
                    } catch { localError = error.localizedDescription }
                    pendingExternalHost = nil
                }
                Button("Отмена", role: .cancel) { pendingExternalHost = nil }
            } message: {
                Text(SmartExclusionsUX.text("Общий IP-адрес может обслуживать и другие сайты. Такой обход касается всего IP, не только выбранного домена."))
            }
            .onAppear {
                entries = model.manualExclusions
                graph = model.smartGraph.pruned()
            }
            .onDisappear { cancelScan() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Brand.text)
                            .frame(width: 44, height: 44)
                            .background(Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppL10n.tr("Отмена"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !saving else { return }
                        cancelScan()
                        if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addEntry() }
                        guard localError == nil else { return }
                        saving = true
                        Task {
                            let success = await model.saveExclusions(entries, graph: graph)
                            saving = false
                            if success { dismiss() }
                        }
                    } label: {
                        Group {
                            if textSize.isAccessibilitySize {
                                Image(systemName: "checkmark")
                                    .font(.title3.weight(.bold))
                                    .frame(width: 48, height: 48)
                            } else {
                                Text(saving ? SmartExclusionsUX.text("Сохранение…") : AppL10n.tr("Сохранить"))
                                    .font(.body.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 44)
                            }
                        }
                        .foregroundStyle(Color.black)
                        .background(Brand.mintLight, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(saving ? SmartExclusionsUX.text("Сохранение…") : AppL10n.tr("Сохранить"))
                    .disabled(saving)
                }
            }
        }
    }

    @ViewBuilder
    private var editorSection: some View {
                Section {
                    Text(SmartExclusionsUX.text("Введите домен, URL или IP и нажмите «Добавить»."))
                        .font(.body)
                        .foregroundStyle(Brand.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Group {
                        if textSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) {
                                domainField
                                addDomainButton
                            }
                        } else {
                            HStack {
                                domainField
                                addDomainButton
                            }
                        }
                    }
                    Text(SmartExclusionsUX.text("Обход VPN — только для разрешённых доменов."))
                        .font(.body)
                        .foregroundStyle(Brand.text)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup {
                        Text(SmartExclusionsUX.text("В обход VPN идут только вручную добавленные домены и связанные домены, которые вы подтвердили. Обнаружение других сайтов само по себе не меняет маршруты. Изменения применятся после сохранения и переподключения."))
                            .font(.body)
                            .foregroundStyle(Brand.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(SmartExclusionsUX.text("Совместимость: для gosuslugi.ru пока сохраняется ранее проверенное исключение gu-st.ru. Автоматический поиск других сторонних ресурсов не включает обход без вашего решения."))
                            .font(.body)
                            .foregroundStyle(Brand.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } label: {
                        Group {
                            if textSize.isAccessibilitySize {
                                Label(SmartExclusionsUX.text("Подробнее о правилах обхода"), systemImage: "info.circle")
                                    .labelStyle(.iconOnly)
                                    .font(.title2)
                                    .frame(minWidth: 44, minHeight: 44)
                            } else {
                                Text(SmartExclusionsUX.text("Подробнее о правилах обхода"))
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityLabel(SmartExclusionsUX.text("Подробнее о правилах обхода"))
                    }
                    if let localError {
                        Text(SmartExclusionsUX.text(localError)).font(.caption).foregroundStyle(.red)
                    }
                    Button {
                        guard !scanUnavailable else { return }
                        scanSite()
                    } label: {
                        Group {
                            if textSize.isAccessibilitySize {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2.weight(.semibold))
                                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            } else {
                                Text(SmartExclusionsUX.text(scanning ? "Идёт анализ…" : "Найти связанные домены"))
                                    .font(.body.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(minHeight: 44, alignment: .leading)
                            }
                        }
                        .foregroundStyle(scanUnavailable ? Brand.text : Brand.mint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SmartExclusionsUX.text(scanning ? "Идёт анализ…" : "Найти связанные домены"))
                    .disabled(scanUnavailable)
                    if scanning {
                        ProgressView(SmartExclusionsUX.text("Анализ ресурсов сайта"))
                        Button(SmartExclusionsUX.text("Отменить анализ")) { cancelScan() }
                    }
                }
    }

    private var scanUnavailable: Bool {
        scanning || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var domainField: some View {
        TextField("example.com", text: $input)
            .focused($isDomainFocused)
            .font(.body)
            .frame(minHeight: 44)
            .accessibilityLabel(SmartExclusionsUX.text("Домен или IP"))
            .accessibilityHint(SmartExclusionsUX.text("Можно вставить домен, URL или IP"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    private var addDomainButton: some View {
        Button { addEntry() } label: {
            Group {
                if textSize.isAccessibilitySize {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                } else {
                    Text("Добавить")
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(AppL10n.tr("Добавить"))
    }

    private func graphEdgeRow(_ edge: SmartDependency, parent: String) -> some View {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(edge.host).textSelection(.enabled)
                                            Spacer()
                                            Text(SmartExclusionsUX.text(edge.decision.label))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(SmartExclusionsUX.text(edge.evidence.description))
                                            .font(.caption2).foregroundStyle(.secondary)
                                        Text(edge.lastSeen, style: .date)
                                            .font(.caption2).foregroundStyle(.secondary)
                                        HStack {
                                            Button(SmartExclusionsUX.text(edge.decision == .approved ? "Отозвать" : "Разрешить")) {
                                                toggleGraphEdge(edge, parent: parent)
                                            }
                                            .buttonStyle(.borderless)
                                            .frame(minHeight: 44)
                                            .accessibilityLabel(SmartExclusionsUX.text(edge.decision == .approved ? "Отозвать" : "Разрешить") + " " + edge.host)
                                            Button(SmartExclusionsUX.text("Удалить"), role: .destructive) {
                                                snapshotUndo()
                                                graph.remove(parent: parent, child: edge.host)
                                            }
                                            .buttonStyle(.borderless)
                                            .frame(minHeight: 44)
                                            .accessibilityLabel(SmartExclusionsUX.text("Удалить") + " " + edge.host)
                                        }
                                    }
    }

    private func toggleGraphEdge(_ edge: SmartDependency, parent: String) {
        do {
            snapshotUndo()
            var next = graph
            let action: SmartDecision = edge.decision == .approved ? .rejected : .approved
            try next.set(action, parent: parent, child: edge.host)
            let manual: [String]
            if edge.decision == .approved {
                manual = entries
            } else {
                manual = try SiteExclusionPolicy.normalizeAll(entries + [parent])
            }
            _ = try next.effective(manual: manual)
            graph = next
            entries = manual
        } catch {
            localError = error.localizedDescription
        }
    }

    private func snapshotUndo() {
        undoEntries = entries
        undoGraph = graph
    }

    private func restoreUndo() {
        guard let saved = undoEntries, let savedGraph = undoGraph else { return }
        entries = saved
        graph = savedGraph
        undoEntries = nil
        undoGraph = nil
        localError = nil
    }

    private func cancelScan() {
        scanner?.cancel()
        scanner = nil
        scanning = false
    }

    private func scanSite() { scanSite(input) }

    private func scanSite(_ site: String) {
        do {
            guard let host = try SiteExclusionPolicy.normalize(site), !host.isEmpty else { return }
            guard SiteDependencyDiscovery.isScannableHost(host) else {
                localError = "Для поиска зависимостей укажите корректный домен сайта, а не IP-адрес"
                return
            }
            scanning = true
            discovered = []
            externalHints = []
            selectedDiscovered = []
            localError = nil
            let worker = ExclusionWebScanner()
            scanner = worker
            worker.scan(host: host) { result in
                guard scanner === worker else { return }
                scanning = false
                scanner = nil
                switch result {
                case .success(let observation):
                    do {
                        snapshotUndo()
                        try graph.observe(parent: host, html: observation.html, network: observation.network)
                        scannedParent = SmartExclusionGraph.root(host) ?? host
                        externalHints = observation.external.filter { !entries.contains($0) }
                        discovered = graph.edges.filter {
                            $0.parent == scannedParent && $0.decision == .pending && !entries.contains($0.host)
                        }.map(\.host).sorted()
                        if discovered.isEmpty { localError = "Новых связанных доменов не обнаружено" }
                    } catch { localError = error.localizedDescription }
                case .failure(let error): localError = error.localizedDescription
                }
            }
        } catch { localError = error.localizedDescription }
    }

    private func addEntry() {
        isDomainFocused = false
        do {
            if let value = try SiteExclusionPolicy.normalize(input) {
                let updated = try SiteExclusionPolicy.normalizeAll(entries + [value])
                _ = try graph.effective(manual: updated)
                if updated != entries { snapshotUndo() }
                entries = updated
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
                Section("Обычное состояние") {
                    Picker("Режим", selection: $mode) {
                        ForEach(IOSAppRoutingMode.allCases) { item in
                            Text(AppL10n.tr(item.title)).tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                    .onChange(of: mode) { newValue in
                        saveAndApplyMode(newValue)
                    }
                }

                Section("Что произойдёт") {
                    Text(AppL10n.tr(modeExplanation)).font(.footnote)
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
#endif
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

private struct SiteScanObservation {
    let html: [String]
    let network: [String]
    let external: [String]
}

/// Ephemeral WebKit scanner; no persistent cookies or implicit VPN changes.
@MainActor
final class ExclusionWebScanner: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var completion: ((Result<SiteScanObservation, Error>) -> Void)?
    private var host = ""

    fileprivate func scan(host: String, completion: @escaping (Result<SiteScanObservation, Error>) -> Void) {
        self.host = host
        self.completion = completion
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: -1, y: -1, width: 1, height: 1), configuration: configuration)
        // WebKit may defer navigation for an unattached zero-sized web view.
        view.isUserInteractionEnabled = false
        view.alpha = 0.01
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .addSubview(view)
        webView = view
        view.navigationDelegate = self
        guard let url = URL(string: "https://" + host) else { finish(.failure(URLError(.badURL))); return }
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak self] in
            self?.finish(.failure(URLError(.timedOut)))
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let destination = navigationAction.request.url,
              destination.scheme?.lowercased() == "https",
              let requested = URL(string: "https://" + host)?.host?.lowercased(),
              destination.host?.lowercased() == requested else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func cancel() {
        completion = nil
        tearDownWebView()
    }

    private func tearDownWebView() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = """
        JSON.stringify({html: document.documentElement.outerHTML.slice(0,512000),
          resources: performance.getEntriesByType('resource').slice(0,512).map(x => x.name)})
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error { self.finish(.failure(error)); return }
            guard let raw = (value as? String)?.data(using: .utf8),
                  let payload = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else {
                self.finish(.failure(URLError(.cannotParseResponse)))
                return
            }
            let html = payload["html"] as? String ?? ""
            let resources = payload["resources"] as? [String] ?? []
            let htmlHosts = SiteDependencyDiscovery.candidates(html: html, for: self.host)
            let networkHosts = SiteDependencyDiscovery.resourceCandidates(urls: resources, for: self.host)
            let external = SiteDependencyDiscovery.externalCandidates(urls: resources, for: self.host)
            self.finish(.success(SiteScanObservation(html: htmlHosts, network: networkHosts, external: external)))
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<SiteScanObservation, Error>) {
        guard let completion else { return }
        self.completion = nil
        tearDownWebView()
        completion(result)
    }
}
