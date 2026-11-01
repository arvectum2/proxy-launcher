"""iOS Home viewport must not use scrolling as a substitute for fitting a banner."""
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / 'mobile/ios/App/ContentView.swift'
PROBE = SRC.with_name('HomeLayoutProbe.swift')


def test_iphone_home_is_a_fixed_unscrollable_dashboard():
    source = SRC.read_text(encoding='utf-8')
    home = source.split('    private var homeScreen: some View {', 1)[1].split('    private func connectionCard', 1)[0]
    assert '#if targetEnvironment(macCatalyst)' in home
    iphone = home.split('#else', 1)[1].split('#endif', 1)[0]
    assert 'ScrollView' not in iphone
    assert 'GeometryReader' in home
    assert '.frame(width: geometry.size.width, height: geometry.size.height' in iphone
    assert 'Spacer(minLength: tight ? 4 : 12)' in iphone
    assert 'VStack(spacing: 0)' in iphone
    assert '.homeMeasured("nativeAd")' in iphone
    assert '.homeMeasured("adStack")' in iphone
    assert 'homeMeasured("banner")' in iphone
    assert 'homeMeasured("connection")' in iphone
    assert 'homeMeasured("profile")' in iphone
    assert 'homeMeasured("header")' in iphone
    assert iphone.index('homeMeasured("header")') < iphone.index('homeMeasured("banner")')
    assert iphone.index('homeMeasured("banner")') < iphone.index('homeMeasured("nativeAd")') < iphone.index('Spacer(minLength: tight ? 4 : 12)') < iphone.index('homeMeasured("connection")')
    assert iphone.index('homeMeasured("connection")') < iphone.index('homeMeasured("profile")')


def test_preview_banner_never_appears_in_release_without_real_ad():
    source = SRC.read_text(encoding='utf-8')
    gate = source.split('    private var bannerPreview: Bool {', 1)[1].split('    private var qaProfile:', 1)[0]
    assert '#if DEBUG' in gate and '#else' in gate
    assert '#else\n        false' in gate
    assert '-aplHomeBannerQA' in gate
    assert 'bannerHeightQA' in source
    assert '100 : 90' in source


def test_critical_controls_remain_accessible_and_translated():
    source = SRC.read_text(encoding='utf-8')
    home = source.split('    private var homeConnectControl: some View {', 1)[1].split('    // Preserve equal-height macOS', 1)[0]
    assert '.disabled(!model.vpn.canToggle)' in home
    assert '.accessibilityLabel(AppL10n.tr(qaActionTitle))' in home
    assert 'Text(AppL10n.tr(qaStatusTitle))' not in home
    assert 'Text(AppL10n.tr(qaStatusTitle))' not in home
    assert 'Text(AppL10n.tr(qaActionTitle))' in home
    assert '.homeMeasured("primaryAction")' in home
    assert 'Menu { profileSelectionMenu }' in home
    assert 'homeProfileLabel(qaProfile ? "QA Proxy" : model.selectedLabel)' in home
    assert '.minimumScaleFactor(' in home
    assert 'showNewProfile = true' in home
    assert '.frame(height: 70)' in home
    assert '.frame(height: 58)' in home


def test_geometry_probe_is_debug_only_and_does_not_require_external_packages():
    s = PROBE.read_text(encoding='utf-8')
    assert '#if DEBUG' in s
    assert 'APLHomeLayoutQA.json' in s
    assert 'JSONSerialization.data' in s
    assert 'HomeFramePreference' in s


def test_larger_real_inline_banner_and_bottom_aligned_actions_with_home_tab_first():
    source = SRC.read_text(encoding='utf-8')
    home = source.split('    private var homeScreen: some View {', 1)[1].split('    private var homeConnectControl', 1)[0]
    shell = source.split('    private var mobileShell: some View {', 1)[1].split('#if targetEnvironment(macCatalyst)', 1)[0]
    assert 'maxAdHeight: inlineCreativeMax' in home
    assert '.frame(height: equalAdHeight, alignment: .top)' in home
    assert home.index('homeMeasured("banner")') < home.index('Spacer(minLength: tight ? 4 : 12)') < home.index('homeConnectControl')
    assert '.padding(.bottom, tight ? 4 : 12)' in home
    assert shell.index('homeScreen') < shell.index('profilesScreen') < shell.index('activityScreen')
    assert 'case .home: return "house.fill"' in source
    assert 'return AppL10n.tr("Домой")' in source


def test_two_ads_and_connect_off_is_outlined():
    src = SRC.read_text(encoding='utf-8')
    home = src.split('private var homeScreen: some View {', 1)[1].split('private var dashboardCardMaxHeight', 1)[0]
    assert 'NativeHomeAdView(width:' in home
    assert 'if geometry.size.height >= 650' in home
    assert 'homeConnectionIsEstablished ? Brand.mint : Brand.surface' in home
    assert 'Text(AppL10n.tr(qaStatusTitle))' not in home
    assert 'Text(AppL10n.tr(qaActionTitle))' in home
    assert 'homeConnectControl' in home
    assert home.index('NativeHomeAdView(width:') < home.index('homeMeasured("adStack")') < home.index('Spacer(minLength: tight ? 4 : 12)') < home.index('homeConnectControl')
    # Only the button owns the status label; no conditional caption shifts height.
    control = home.split('private var homeConnectControl: some View {', 1)[1].split('private var homeProfileControl:', 1)[0]
    assert 'Text(AppL10n.tr(qaStatusTitle))' not in control
    assert 'if homeConnectionIsTransitioning {' in control
    assert 'ProgressView()' in control
    assert 'stop.circle.fill' not in control
    assert 'arrow.right.circle.fill' not in control
    assert 'Image(systemName: model.profiles.isEmpty' in control
    assert 'ProgressView()' in control
    assert '.frame(height: 70)' in control
    assert 'Text(AppL10n.tr(qaActionTitle))' in control

def test_settings_is_compact_and_ungrouped_port():
    src = SRC.read_text(encoding='utf-8')
    settings = src.split('private var compactSettingsContent: some View {',1)[1].split('private func compactSettingsAction',1)[0]
    assert 'sectionTitle("Настройки", subtitle:' not in settings
    assert 'Системная тема автоматически следует' not in settings
    assert 'Выберите язык интерфейса' not in settings
    assert 'Text(AppL10n.tr("Язык"))' in settings
    assert 'Picker("Язык приложения"' in settings
    assert 'compactAutomaticRoutingSettings' in settings
    assert 'ViewThatFits(in: .vertical)' in src
    assert 'Toggle(isOn: Binding(' in src
    assert 'String(profile.port)' in src


def test_native_ad_reserves_fixed_height_in_loading_and_no_fill():
    native = SRC.with_name('NativeHomeAdView.swift').read_text(encoding='utf-8')
    assert '.frame(height: height, alignment: .top)' in native
    assert 'SettingsBannerView(adWidth: width, maxAdHeight: 76' in native
    src = SRC.read_text(encoding='utf-8')
    assert 'case "off": return "Подключиться"' in src
