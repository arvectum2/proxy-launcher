import SwiftUI
import NetworkExtension
import UIKit

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
    // Crop only the original brand symbol; the full product title is one text style.
    static var symbol: Image {
        if let path = Bundle.main.path(forResource: "ArvectumWordmark", ofType: "png"),
           let image = UIImage(contentsOfFile: path),
           let original = image.cgImage,
           let cropped = original.cropping(to: CGRect(x: 0, y: 0, width: 182, height: 120)) {
            return Image(uiImage: UIImage(cgImage: cropped))
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
        case .home:
#if targetEnvironment(macCatalyst)
            return AppL10n.tr("Главная")
#else
            return AppL10n.tr("Домой")
#endif
        case .profiles: return AppL10n.tr("Профили")
        case .activity: return AppL10n.tr("Активность")
        case .settings: return AppL10n.tr("Настройки")
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
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
    @State private var openImportAfterGuide = false
    @State private var destination: AppDestination = .home
    @State private var editorProfile: ProxyProfile?
    @State private var showNewProfile = false
    @State private var importRequest: ProxyImportRequest?
    @State private var showProfileBackup = false
    @State private var profileSearch = ""
    @FocusState private var profileSearchFocused: Bool
    @State private var profileGroupFilter = "all"
    @State private var pendingGroupIDs: Set<UUID> = []
    @State private var customGroupName = ""
    @State private var showNewProfileGroup = false
    @State private var profileBulkMode = false
    @State private var bulkSelectedIDs: Set<UUID> = []
    @State private var confirmBulkDelete = false
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

            Text(AppShared.version)
                .font(.caption2)
                .foregroundStyle(Brand.mintLight.opacity(0.72))
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
                                        Label("\(Int(bannerHeightQA)) pt banner layout QA", systemImage: "rectangle.on.rectangle")
                                            .font(.caption2).foregroundStyle(Brand.softGray)
                                    }
                                    .frame(height: tight ? 60 : bannerHeightQA)
                            } else {
                                SettingsBannerView(
                                    adWidth: geometry.size.width,
                                    maxAdHeight: tight ? 120 : (compact ? 160 : 220)
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .homeMeasured("banner")

                        if geometry.size.height >= 650 {
                            Group {
                                if bannerPreview {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Brand.surface)
                                        .frame(height: 52)
                                } else {
                                    NativeHomeAdView(width: geometry.size.width,
                                                     height: compact ? 150 : 205)
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
        ZStack {
            Brand.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
#if !targetEnvironment(macCatalyst)
                    header
#endif
                    HStack(spacing: 8) {
                        cardButton("Добавить", filled: true) { showNewProfile = true }
                        cardButton("Импорт", filled: false) {
                            importRequest = ProxyImportRequest(source: "")
                        }
                        .accessibilityIdentifier("profiles.import")
                        cardButton("Копия", filled: false) { showProfileBackup = true }
                            .accessibilityLabel(AppL10n.tr("Резервные копии"))
                            .accessibilityIdentifier("profiles.encryptedBackup")
                    }
                    if model.profiles.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tray")
                                .font(.system(size: 32, weight: .light))
                                .accessibilityHidden(true)
                            Text(AppL10n.tr("Нет прокси"))
                                .font(.subheadline)
                        }
                        .foregroundStyle(Brand.softGray)
                        .frame(maxWidth: .infinity, minHeight: 150)
                        .accessibilityIdentifier("profiles.emptyState")
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(AppL10n.tr("Профили")).font(.headline).foregroundStyle(Brand.text)
                                Spacer()
                                Button(profileBulkMode ? AppL10n.tr("Готово") : AppL10n.tr("Выбрать")) {
                                    profileBulkMode.toggle()
                                    bulkSelectedIDs.removeAll()
                                }
                                .foregroundStyle(Brand.mint)
                            }
                            HStack {
                                Button {
                                    Task { await model.scanProfiles(manual: true) }
                                } label: {
                                    Label(model.isScanningProfiles ? AppL10n.tr("Проверка…") : AppL10n.tr("Проверить"), systemImage: "waveform.path.ecg")
                                }
                                .disabled(model.isScanningProfiles)
                                .accessibilityHint(AppL10n.tr("Проверить следующие 10 прокси"))
                                Spacer()
                                if model.isScanningProfiles { ProgressView() }
                            }
                            if !model.lastProfileScanSummary.isEmpty {
                                Text(model.lastProfileScanSummary)
                                    .font(.caption).foregroundStyle(Brand.softGray)
                            }
                            HStack(spacing: 4) {
                                TextField(AppL10n.tr("Поиск по названию или адресу"), text: $profileSearch)
                                    .focused($profileSearchFocused)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                                    .onSubmit { profileSearchFocused = false }
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("profiles.search")
                                if profileSearchFocused {
                                    Button { profileSearchFocused = false } label: {
                                        Image(systemName: "keyboard.chevron.compact.down")
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Brand.mintLight)
                                    .accessibilityLabel(AppL10n.tr("Готово"))
                                    .accessibilityIdentifier("keyboard.dismiss.search")
                                }
                            }
                            Menu {
                                Button(AppL10n.tr("Все профили")) { profileGroupFilter = "all" }
                                Button(AppL10n.tr("Избранные")) { profileGroupFilter = "favorites" }
                                ForEach(model.profileOrganization.groupNames, id: \.self) { group in
                                    Button(AppL10n.tr(group)) { profileGroupFilter = "group:" + group }
                                }
                            } label: {
                                Label(profileGroupFilter == "all" ? AppL10n.tr("Все профили") :
                                      profileGroupFilter == "favorites" ? AppL10n.tr("Избранные") :
                                      AppL10n.tr(String(profileGroupFilter.dropFirst(6))),
                                      systemImage: "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(Brand.mintLight)
                            }
                            ForEach(visibleProfiles) { profile in
                                HStack(spacing: 10) {
                                    Button {
                                        if profileBulkMode {
                                            if !bulkSelectedIDs.insert(profile.id).inserted {
                                                bulkSelectedIDs.remove(profile.id)
                                            }
                                        } else { editorProfile = profile }
                                    } label: {
                                        HStack(spacing: 10) {
                                            if profileBulkMode {
                                                Image(systemName: bulkSelectedIDs.contains(profile.id) ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(Brand.mint)
                                            }
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack(spacing: 5) {
                                                    Text(profile.name)
                                                        .font(.subheadline.weight(.semibold))
                                                    if !model.automaticSelection && model.selectedProfileID == profile.id {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.caption)
                                                            .foregroundStyle(Brand.mintLight)
                                                            .accessibilityLabel(AppL10n.tr("Текущий профиль"))
                                                    }
                                                }
                                                Text("\(profile.host):\(String(profile.port)) · \(profile.type.rawValue)")
                                                    .font(.caption).foregroundStyle(Brand.softGray)
                                                    // Host, port and protocol are LTR technical
                                                    // identifiers even inside Arabic/Hebrew UI.
                                                    .environment(\.layoutDirection, .leftToRight)
                                                if let group = model.profileOrganization.group(for: profile.id) {
                                                    Text(AppL10n.tr(group)).font(.caption2).foregroundStyle(Brand.mintLight)
                                                }
                                                if let state = model.health[profile.id] {
                                                    Label(state.label, systemImage: "waveform.path.ecg")
                                                        .font(.caption2)
                                                        .foregroundStyle(Brand.softGray)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .foregroundStyle(Brand.text)
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("profiles.row.\(profile.id.uuidString)")
                                    if !profileBulkMode {
                                        Button { model.toggleFavorite(profile.id) } label: {
                                            Image(systemName: model.profileOrganization.isFavorite(profile.id) ? "star.fill" : "star")
                                                .foregroundStyle(Brand.mint)
                                                .frame(minWidth: 44, minHeight: 44)
                                        }
                                        .accessibilityLabel(model.profileOrganization.isFavorite(profile.id) ? AppL10n.tr("Убрать из избранного") : AppL10n.tr("В избранное"))
                                        profileGroupMenu(ids: [profile.id])
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            if visibleProfiles.isEmpty {
                                Text(AppL10n.tr("Нет профилей по выбранному фильтру"))
                                    .font(.footnote).foregroundStyle(Brand.softGray)
                            }
                            if profileBulkMode {
                                HStack(spacing: 10) {
                                    Text(String(format: AppL10n.tr("Выбрано: %d"), selectedVisibleIDs.count))
                                        .font(.footnote).foregroundStyle(Brand.softGray)
                                    Spacer()
                                    Menu {
                                        Button(AppL10n.tr("Выбрать все")) {
                                            bulkSelectedIDs = Set(visibleProfiles.map(\.id))
                                        }
                                        .disabled(visibleProfiles.isEmpty)
                                        Button(AppL10n.tr("Снять выбор")) { bulkSelectedIDs.removeAll() }
                                            .disabled(selectedVisibleIDs.isEmpty)
                                        Divider()
                                        Button(AppL10n.tr("В избранное")) {
                                            model.setFavorites(selectedVisibleIDs, enabled: true)
                                        }
                                        Button(AppL10n.tr("Убрать из избранного")) {
                                            model.setFavorites(selectedVisibleIDs, enabled: false)
                                        }
                                        profileGroupMenu(ids: selectedVisibleIDs)
                                        Button(AppL10n.tr("Проверить")) {
                                            Task { await model.scanProfiles(manual: true, specificIDs: selectedVisibleIDs) }
                                        }
                                        .disabled(selectedVisibleIDs.count == 0 || selectedVisibleIDs.count > 10 || model.isScanningProfiles)
                                    } label: {
                                        Label(AppL10n.tr("Действия"), systemImage: "ellipsis.circle")
                                    }
                                    .disabled(visibleProfiles.isEmpty)
                                    Button(AppL10n.tr("Удалить"), role: .destructive) {
                                        confirmBulkDelete = true
                                    }
                                    .disabled(selectedVisibleIDs.isEmpty || model.vpn.isConnectedOrConnecting)
                                    .accessibilityHint(AppL10n.tr("Удаление требует отключить VPN"))
                                }
                            }
                        }
                        .padding(16)
                        .background(Brand.graphite)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: profileSearch) { _ in bulkSelectedIDs.removeAll() }
        .onChange(of: profileGroupFilter) { _ in bulkSelectedIDs.removeAll() }
        .alert(AppL10n.tr("Новая группа"), isPresented: $showNewProfileGroup) {
            TextField(AppL10n.tr("Название группы"), text: $customGroupName)
            Button(AppL10n.tr("Сохранить")) {
                let name = customGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { model.assignProfileGroup(name, to: pendingGroupIDs) }
                pendingGroupIDs.removeAll()
            }
            Button(AppL10n.tr("Отмена"), role: .cancel) { pendingGroupIDs.removeAll() }
        } message: {
            Text(AppL10n.tr("Группы изменяют только организацию списка, не маршрутизацию VPN."))
        }
        .confirmationDialog(AppL10n.tr("Удалить выбранные прокси?"), isPresented: $confirmBulkDelete, titleVisibility: .visible) {
            Button(AppL10n.tr("Удалить безвозвратно"), role: .destructive) {
                guard !model.vpn.isConnectedOrConnecting else { return }
                let removed = model.deleteProfiles(ids: selectedVisibleIDs)
                bulkSelectedIDs.subtract(removed)
                if bulkSelectedIDs.isEmpty { profileBulkMode = false }
            }
        } message: {
            Text(AppL10n.tr("Профили и сохранённые пароли будут удалены без возможности восстановления."))
        }
    }

    /// Destructive operations never act on profiles hidden by search or a
    /// group filter, even if the selection was made before filtering.
    private var selectedVisibleIDs: Set<UUID> {
        bulkSelectedIDs.intersection(Set(visibleProfiles.map(\.id)))
    }

    private var visibleProfiles: [ProxyProfile] {
        model.profiles.filter { profile in
            let matchesSearch = profileSearch.isEmpty ||
                profile.name.localizedCaseInsensitiveContains(profileSearch) ||
                profile.host.localizedCaseInsensitiveContains(profileSearch)
            let matchesGroup: Bool
            switch profileGroupFilter {
            case "all": matchesGroup = true
            case "favorites": matchesGroup = model.profileOrganization.isFavorite(profile.id)
            default:
                matchesGroup = profileGroupFilter.hasPrefix("group:") &&
                    model.profileOrganization.group(for: profile.id) == String(profileGroupFilter.dropFirst(6))
            }
            return matchesSearch && matchesGroup
        }.sorted { lhs, rhs in
            let leftFavorite = model.profileOrganization.isFavorite(lhs.id)
            let rightFavorite = model.profileOrganization.isFavorite(rhs.id)
            if leftFavorite != rightFavorite { return leftFavorite }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func profileGroupMenu(ids: Set<UUID>) -> some View {
        Menu {
            Button(AppL10n.tr("Без группы")) { model.assignProfileGroup(nil, to: ids) }
            ForEach(Array(Set(["Основные", "Рабочие", "Резервные"] + model.profileOrganization.groupNames)).sorted(), id: \.self) { group in
                Button(AppL10n.tr(group)) { model.assignProfileGroup(group, to: ids) }
            }
            Button(AppL10n.tr("Новая группа…")) {
                pendingGroupIDs = ids
                customGroupName = ""
                showNewProfileGroup = true
            }
        } label: {
            Label(AppL10n.tr("Группа"), systemImage: "folder.badge.plus")
                .foregroundStyle(Brand.mintLight)
                .frame(minHeight: 44)
        }
        .accessibilityLabel(AppL10n.tr("Группа профиля"))
    }

    private var activityScreen: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
#if !targetEnvironment(macCatalyst)
                    header
#endif
                    Text(AppL10n.tr("Активность"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Brand.text)
                    HStack {
                        // Raw NetworkExtension IPC errors are not actionable
                        // product copy. Keep diagnostics in Journal, display a
                        // localized explanation on the overview.
                        Label(AppL10n.tr(model.vpn.detail.contains("IPC failed")
                                       ? "Не удалось открыть VPN-сессию" : model.vpn.detail),
                              systemImage: "bolt.horizontal.circle")
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
    /// On regular iPhones the entire Settings overview fits without scrolling.
    /// Smaller devices and Accessibility text sizes get a scrollable fallback,
    /// never hidden or clipped controls.
    private var compactSettingsScreen: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()
            GeometryReader { geometry in
                Group {
                    if #available(iOS 16.0, *) {
                        ViewThatFits(in: .vertical) {
                            compactSettingsContent
                            ScrollView { compactSettingsContent }
                        }
                    } else {
                        // Keep all settings reachable on iOS 15 too.
                        ScrollView { compactSettingsContent }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height,
                       alignment: .top)
            }
        }
    }

    private var compactSettingsContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
                .padding(.bottom, 4)

            HStack(spacing: 10) {
                Text(AppL10n.tr("Тема"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.text)
                Spacer(minLength: 4)
                Picker("Тема оформления", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .accessibilityIdentifier("settings.theme")
            }
            .modifier(CompactSettingsSurface())

            HStack(spacing: 10) {
                Text(AppL10n.tr("Язык"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.text)
                Spacer(minLength: 4)
                Picker("Язык приложения", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Brand.mintLight)
                .accessibilityIdentifier("settings.language")
            }
            .modifier(CompactSettingsSurface())

            compactSettingsAction("Первое подключение", icon: "questionmark.circle") {
                showSetupGuide = true
            }
            compactSettingsAction("Исключения сайтов", icon: "globe") {
                showExclusions = true
            }
            if #available(iOS 16.0, *) {
                compactSettingsAction("Команды VPN", icon: "bolt.circle") {
                    showQuickActions = true
                }
                .accessibilityIdentifier("settings.quickActions")
            }
            compactSettingsAction("Автоматизация приложений", icon: "app.badge") {
                showAppExclusions = true
            }

            // The existing screenshot QA flag can also preview this row on
            // a disposable simulator without writing any Keychain profiles.
            if !model.profiles.isEmpty || qaProfile {
                compactAutomaticRoutingSettings
            }
            HStack {
                Text(AppL10n.tr("Версия"))
                Spacer()
                Text(AppShared.version)
            }
            .font(.caption)
            .foregroundStyle(Brand.softGray)
            .padding(.horizontal, 10)
            .padding(.top, 3)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func compactSettingsAction(_ title: String, icon: String,
                                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 21)
                Text(AppL10n.tr(title))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Brand.softGray)
            }
            .foregroundStyle(Brand.text)
            .modifier(CompactSettingsSurface())
        }
        .buttonStyle(.plain)
    }

    private var compactAutomaticRoutingSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Text(AppL10n.tr("Основной прокси"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.text)
                Spacer(minLength: 4)
                Menu {
                    ForEach(model.profiles) { profile in
                        Button { model.setPrimary(profile) } label: {
                            Label(profile.name,
                                  systemImage: profile.id == model.primaryProfileID
                                    ? "checkmark.circle.fill" : "circle")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.profiles.first(where: { $0.id == model.primaryProfileID })?.name
                             ?? AppL10n.tr("Выбрать"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(Brand.mintLight)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: 170, alignment: .trailing)
                }
                .accessibilityIdentifier("settings.primaryProfile")
            }
            Toggle(isOn: Binding(
                get: { model.returnToPrimary },
                set: { model.setReturnToPrimary($0) }
            )) {
                Text(AppL10n.tr("Возвращаться к основному"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.text)
            }
            .tint(Brand.mint)
            .accessibilityIdentifier("settings.returnToPrimary")
            .accessibilityHint(AppL10n.tr("Выкл. — меньше переключений: работаем через резервный, пока он доступен. Действует в режиме Авто."))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Brand.graphite, in: RoundedRectangle(cornerRadius: 13))
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
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
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

    private var connectionStatusColor: Color {
        switch model.vpn.status {
        case .connected: return Brand.mintLight
        case .connecting, .reasserting: return Brand.mint
        default: return Brand.softGray
        }
    }

}

private struct CompactSettingsSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Brand.graphite, in: RoundedRectangle(cornerRadius: 13))
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
