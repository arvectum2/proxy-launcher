import SwiftUI

private struct ProxyImportRequest: Identifiable {
    let id = UUID()
    let source: String
}

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("appearanceMode.v1") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("appLanguage.v1") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("setupGuideSeen.v1") private var setupGuideSeen = false
    @State private var showSetupGuide = false
    @State private var openProfileAfterGuide = false
    @State private var openImportAfterGuide = false
    @State private var destination: AppDestination = .home
    @State private var editorProfile: ProxyProfile?
    @State private var showNewProfile = false
    @State private var importRequest: ProxyImportRequest?
    @State private var showProfileBackup = false
    @State private var showExclusions = false
    @State private var showQuickActions = false
    @State private var showAppExclusions = false
#if !targetEnvironment(macCatalyst)
    @StateObject private var homeNativeAdController = HomeNativeAdController()
#endif

    var body: some View {
        Group {
#if targetEnvironment(macCatalyst)
            desktopShell
#else
            mobileShell
#endif
        }
        .task {
#if !targetEnvironment(macCatalyst)
            // SDK is initialized in App.init. Request native ad as soon as the
            // home experience is created; do not render it offscreen to force
            // an impression. Hold this controller across tab switches.
            homeNativeAdController.load()
#endif
            await model.prepare()
#if DEBUG && !targetEnvironment(macCatalyst)
            // Safe screenshot-only localization QA on a disposable simulator.
            // No VPN or saved profile mutation and compiled out of Release.
            if ProcessInfo.processInfo.arguments.contains("-aplSettingsLocaleQA") {
                destination = .settings
            }
#endif
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
            } else if openImportAfterGuide {
                openImportAfterGuide = false
                importRequest = ProxyImportRequest(source: "")
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
                },
                onImportProxy: {
                    setupGuideSeen = true
                    openImportAfterGuide = true
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
        .sheet(isPresented: $showProfileBackup) {
            ProfileBackupView().environmentObject(model)
        }
        .onOpenURL { url in
            do {
                importRequest = ProxyImportRequest(source: try ProxyImport.fromDeepLink(url))
            } catch { model.errorMessage = ProxyImportUX.error(error) }
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
        // The native tab bar is always the last element on screen. Home owns
        // the banner directly below the wordmark, above both main actions.
        // Other tabs are not pushed up by an ad footer.
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
        HStack(alignment: .center, spacing: 7) {
            Brand.symbol
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 25)
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(Brand.logoBacking, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            Text("Arvectum Proxy Launcher")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.mint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            // The version is always available in Settings. At Accessibility
            // sizes the full product name has priority over this metadata.
            if !dynamicTypeSize.isAccessibilitySize {
                Text(AppShared.version)
                    .font(.caption2)
                    .foregroundStyle(Brand.mintLight.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case "off": return "Подключиться" // DEBUG-only Home layout preview
        default: return primaryActionTitle
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
                let edge: CGFloat = compact ? 12 : 18
                // Share the whole available ad footprint equally. The *creative*
                // is still adaptive: Yandex .inline(width:maxHeight:) chooses
                // its own dimensions inside this flexible, screen-sized slot.
                // Reserve enough for both bottom actions and the native tab bar.
                let topInset = tight ? 6.0 : (compact ? 9.0 : 14.0)
                let controlsHeight = 70.0 + 58.0 + gap + (tight ? 4.0 : 12.0)
                let minimumGap = tight ? 4.0 : 12.0
                let headerBudget = 47.0
                let roomForAds = max(0, geometry.size.height - controlsHeight
                    - minimumGap - headerBudget - topInset)
                // On very short screens the native slot is omitted, so allow
                // the surviving inline banner to use the whole safe budget.
                let visibleAdSlots: CGFloat = geometry.size.height >= 650 ? 2 : 1
                let equalAdHeight = min(236.0, floor(roomForAds / visibleAdSlots))
                let inlineCreativeMax = max(1.0, equalAdHeight - 18.0)
                VStack(spacing: 0) {
                    // Both ads are one top-anchored, zero-gap stack. The only
                    // flexible space belongs below ads, above the fixed-height
                    // Connect/profile controls, so VPN state changes cannot
                    // move a banner or the primary action vertically.
                    header
                        .padding(.horizontal, edge)
                        .homeMeasured("header")

                    VStack(spacing: 0) {
                        Group {
                            if bannerPreview {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Brand.surface)
                                    .overlay {
                                        Label("\(Int(equalAdHeight)) pt banner layout QA", systemImage: "rectangle.on.rectangle")
                                            .font(.caption2).foregroundStyle(Brand.softGray)
                                    }
                                    .frame(height: equalAdHeight)
                            } else {
                                SettingsBannerView(
                                    adWidth: geometry.size.width,
                                    maxAdHeight: inlineCreativeMax
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: equalAdHeight, alignment: .top)
                        .homeMeasured("banner")

                        if geometry.size.height >= 650 {
                            Group {
                                if bannerPreview {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Brand.surface)
                                        .frame(height: equalAdHeight)
                                } else {
                                    NativeHomeAdView(width: geometry.size.width,
                                                     height: equalAdHeight,
                                                     controller: homeNativeAdController)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .homeMeasured("nativeAd")
                        }
                    }
                    .homeMeasured("adStack")

                    Spacer(minLength: tight ? 4 : 12)

                    VStack(spacing: gap) {
                        homeConnectControl
                            .homeMeasured("connection")
                        homeProfileControl
                            .homeMeasured("profile")
                    }
                    .frame(maxWidth: 580)
                    .padding(.horizontal, edge)
                    .padding(.bottom, tight ? 4 : 12)
                }
                .padding(.top, tight ? 6 : (compact ? 9 : 14))
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
    /// iPhone Home: one fixed-height stateful action and one profile selector.
    /// The larger multi-control cards remain available on macOS Catalyst.
    private var homeConnectionIsEstablished: Bool {
        qaState == "connected" || model.vpn.status == .connected || model.vpn.status == .reasserting
    }

    private var homeConnectionIsTransitioning: Bool {
        qaState == "connecting" || qaState == "disconnecting" ||
        model.vpn.status == .connecting || model.vpn.status == .disconnecting ||
        model.vpn.status == .reasserting
    }

    private var homeConnectControl: some View {
        Button {
            if model.profiles.isEmpty && !model.vpn.isConnectedOrConnecting {
                showNewProfile = true
            } else {
                Task { await model.toggleVPN() }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: model.profiles.isEmpty && !qaProfile && !model.vpn.isConnectedOrConnecting
                    ? "plus.circle.fill" : "power")
                    .font(.system(size: 24, weight: .bold))
                    .accessibilityHidden(true)
                Text(AppL10n.tr(qaActionTitle))
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                // Keep only the left power icon. Progress, when needed,
                // appears beside the title and never shifts the button.
                if homeConnectionIsTransitioning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(homeConnectionIsEstablished ? Brand.actionText : Brand.mintLight)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(homeConnectionIsEstablished ? Brand.actionText : Brand.mintLight)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(homeConnectionIsEstablished ? Brand.mint : Brand.surface,
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Brand.mint.opacity(homeConnectionIsEstablished ? 0.9 : 0.7), lineWidth: 1.5)
            }
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
    }

    private var homeProfileControl: some View {
        Group {
            if model.profiles.isEmpty && !qaProfile {
                Button { showNewProfile = true } label: {
                    homeProfileLabel(AppL10n.tr("Добавить прокси"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppL10n.tr("Добавить прокси"))
            } else {
                Menu { profileSelectionMenu } label: {
                    homeProfileLabel(qaProfile ? "QA Proxy" : model.selectedLabel)
                }
                .accessibilityLabel(AppL10n.tr("Прокси") + ": " + model.selectedLabel)
            }
        }
    }

    private func homeProfileLabel(_ name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 19, weight: .medium))
                .accessibilityHidden(true)
            Text(name)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Brand.text)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
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
        }
        .padding(compact ? 11 : 18)
        .frame(maxWidth: .infinity, maxHeight: dashboardCardMaxHeight, alignment: .top)
        .background(Brand.graphite)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func activeProfileCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 12) {
            Text(AppL10n.tr("Прокси"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Brand.mintLight)
            Text(model.profiles.isEmpty && !qaProfile ? AppL10n.tr("Прокси пока нет") : (qaProfile ? "QA Proxy" : model.selectedLabel))
                .font(compact ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(Brand.text)
                .lineLimit(1)
            if model.profiles.isEmpty && !qaProfile {
                Text(AppL10n.tr("Нет прокси"))
                    .font(.footnote)
                    .foregroundStyle(Brand.softGray)
            } else {
                Menu {
                    profileSelectionMenu
                } label: {
                    HStack {
                        Text(AppL10n.tr("Сменить"))
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
            }
        }
        .padding(compact ? 9 : 18)
        .frame(maxWidth: .infinity, maxHeight: dashboardCardMaxHeight, alignment: .topLeading)
        .background(Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var profilesScreen: some View {
        ProfilesScreenView(
            model: model,
            editorProfile: $editorProfile,
            showNewProfile: $showNewProfile,
            showProfileBackup: $showProfileBackup,
            onImport: { importRequest = ProxyImportRequest(source: "") },
            header: header
        )
    }

    private var activityScreen: some View {
        ActivityScreenView(model: model, statusColor: connectionStatusColor, header: header)
    }

    private var settingsScreen: some View {
#if targetEnvironment(macCatalyst)
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
#else
        compactSettingsScreen
#endif
    }

#if !targetEnvironment(macCatalyst)
    private var compactSettingsScreen: some View {
        CompactSettingsView(
            model: model,
            appearanceMode: $appearanceMode,
            appLanguage: $appLanguage,
            showSetupGuide: $showSetupGuide,
            showExclusions: $showExclusions,
            showQuickActions: $showQuickActions,
            showAppExclusions: $showAppExclusions,
            qaProfile: qaProfile,
            header: header
        )
    }
#endif

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
                Label(profile.name,
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

    private var connectionStatusColor: Color {
        switch model.vpn.status {
        case .connected: return Brand.mintLight
        case .connecting, .reasserting: return Brand.mint
        default: return Brand.softGray
        }
    }

}
