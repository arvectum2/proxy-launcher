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
    assert 'Spacer(minLength: 0)' in iphone
    assert 'homeMeasured("banner")' in iphone
    assert 'homeMeasured("connection")' in iphone
    assert 'homeMeasured("profile")' in iphone
    assert 'homeMeasured("header")' in iphone


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
    home = source.split('    private func connectionCard(', 1)[1].split('    private var profilesScreen:', 1)[0]
    assert '.disabled(!model.vpn.canToggle)' in home
    assert '.accessibilityLabel(AppL10n.tr(qaActionTitle))' in home
    for text in ('Соединение', 'Выбор прокси', 'Выбрать профиль',
                 'Добавьте первый прокси, чтобы начать. Понадобятся адрес и порт.'):
        assert f'AppL10n.tr("{text}")' in home
    assert '.minimumScaleFactor(' in home
    assert 'if !compact {' in home  # secondary controls move to Profiles tab
    assert 'showNewProfile = true' in home
    assert 'destination = .profiles' in home
    assert '.frame(height: compact ? 44 : 52)' in home


def test_geometry_probe_is_debug_only_and_does_not_require_external_packages():
    s = PROBE.read_text(encoding='utf-8')
    assert '#if DEBUG' in s
    assert 'APLHomeLayoutQA.json' in s
    assert 'JSONSerialization.data' in s
    assert 'HomeFramePreference' in s
