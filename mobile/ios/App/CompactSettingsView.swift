import SwiftUI

/// iPhone-only compact Settings. All edits are bindings to the existing model,
/// no separate settings store or duplicated VPN state.
#if !targetEnvironment(macCatalyst)
struct CompactSettingsView<Header: View>: View {
    @ObservedObject var model: AppViewModel
    @Binding var appearanceMode: String
    @Binding var appLanguage: String
    @Binding var showSetupGuide: Bool
    @Binding var showExclusions: Bool
    @Binding var showQuickActions: Bool
    @Binding var showAppExclusions: Bool
    let qaProfile: Bool
    let header: Header
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// On regular iPhones the entire Settings overview fits without scrolling.
    /// Smaller devices and Accessibility text sizes get a scrollable fallback,
    /// never hidden or clipped controls.
    var body: some View {
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

    private var themePicker: some View {
        Picker("Тема оформления", selection: $appearanceMode) {
            ForEach(AppearanceMode.allCases) { mode in
                Text(mode.title).tag(mode.rawValue)
            }
        }
        .accessibilityLabel(AppL10n.tr("Тема оформления"))
        .accessibilityIdentifier("settings.theme")
    }

    @ViewBuilder
    private var adaptiveThemePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            themePicker.pickerStyle(.menu)
        } else {
            themePicker.pickerStyle(.segmented)
                .frame(maxWidth: 240)
        }
    }

    /// A horizontal row is compact at normal text sizes. At Accessibility
    /// sizes it becomes a vertical label/control pair, so translated labels
    /// and the current menu value have their full available width.
    private func settingsRow<Control: View>(
        _ title: String, @ViewBuilder control: () -> Control
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppL10n.tr(title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.text)
                        .fixedSize(horizontal: false, vertical: true)
                    control()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 3)
            } else {
                HStack(spacing: 10) {
                    Text(AppL10n.tr(title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.text)
                    Spacer(minLength: 4)
                    control()
                }
            }
        }
        .modifier(CompactSettingsSurface())
    }

    private var compactSettingsContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
                .padding(.bottom, 4)

            settingsRow("Тема") {
                adaptiveThemePicker
            }

            settingsRow("Язык") {
                Picker("Язык приложения", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Brand.mintLight)
                .accessibilityLabel(AppL10n.tr("Язык приложения"))
                .accessibilityIdentifier("settings.language")
            }

            compactSettingsAction("Первое подключение", icon: "questionmark.circle") {
                showSetupGuide = true
            }
            compactSettingsAction("Исключения сайтов", icon: "globe") {
                showExclusions = true
            }
            .accessibilityIdentifier("settings.siteExclusions")
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
                Image(systemName: icon)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 22 : 18))
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 34 : 21)
                    .accessibilityHidden(true)
                Text(AppL10n.tr(title))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 17 : 13, weight: .medium))
                    .foregroundStyle(Brand.softGray)
                    .accessibilityHidden(true)
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
                .accessibilityLabel(AppL10n.tr("Основной прокси") + ": " +
                                    (model.profiles.first(where: { $0.id == model.primaryProfileID })?.name
                                     ?? AppL10n.tr("Выбрать")))
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
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings.returnToPrimary")
            .accessibilityHint(AppL10n.tr("Выкл. — меньше переключений: работаем через резервный, пока он доступен. Действует в режиме Авто."))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Brand.graphite, in: RoundedRectangle(cornerRadius: 13))
    }

}
#endif

/// Default iPhone overview stays compact; larger Dynamic Type sizes can
/// increase row heights, and ViewThatFits switches to a scrollable fallback.
struct CompactSettingsSurface: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 9 : 0)
            .frame(minHeight: 44)
            .background(Brand.graphite, in: RoundedRectangle(cornerRadius: 13))
    }
}
