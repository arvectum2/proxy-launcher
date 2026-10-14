import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
STORE = ROOT / "mobile" / "macos-appstore"
PROJECT = (STORE / "project.yml").read_text(encoding="utf-8")
FETCH = (STORE / "Tools" / "fetch_tun2proxy.py").read_text(encoding="utf-8")
APP_SHARED = (STORE / "Shared" / "AppShared.swift").read_text(encoding="utf-8")
APP_ENTRY = (STORE / "App" / "ArvectumProxyLauncherMacApp.swift").read_text(encoding="utf-8")
HELP = (STORE / "App" / "HelpView.swift").read_text(encoding="utf-8")
VPN = (STORE / "App" / "VPNController.swift").read_text(encoding="utf-8")
EXPORT = (STORE / "Tools" / "export_appstore.sh").read_text(encoding="utf-8")
PROVISIONING = (STORE / "Tools" / "appstore_provisioning.sh").read_text(encoding="utf-8")
ROTATE = (STORE / "Tools" / "rotate_installer_certificate.sh").read_text(encoding="utf-8")


def plist(path):
    with path.open("rb") as stream:
        return plistlib.load(stream)


class MacOSAppStoreContractTests(unittest.TestCase):
    def test_store_lane_is_separate_from_developer_id_bundle(self):
        self.assertIn("ru.arvectum.proxylauncher.macos", PROJECT)
        self.assertIn("ru.arvectum.proxylauncher.macos.PacketTunnel", PROJECT)
        self.assertNotIn("Developer ID Application", PROJECT)
        self.assertIn('CODE_SIGN_IDENTITY: "Apple Distribution"', PROJECT)
    def test_catalyst_is_explicit_and_does_not_derive_bundle_identifier(self):
        self.assertIn("SUPPORTS_MACCATALYST: YES", PROJECT)
        self.assertIn("DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER: NO", PROJECT)
        self.assertIn('MACCATALYST_DEPLOYMENT_TARGET: "16.0"', PROJECT)

    def test_arm64_only_store_lane_requires_macos_13_or_newer(self):
        self.assertIn("ARCHS: arm64", PROJECT)
        self.assertIn('iOS: "16.0"', PROJECT)
        self.assertIn('MACCATALYST_DEPLOYMENT_TARGET: "16.0"', PROJECT)
        self.assertNotIn('MACOSX_DEPLOYMENT_TARGET:', PROJECT)

    def test_app_and_extension_are_sandboxed_network_extension_clients(self):
        app = plist(STORE / "Config" / "App.entitlements")
        tunnel = plist(STORE / "Config" / "PacketTunnel.entitlements")
        for entitlements in (app, tunnel):
            self.assertIs(entitlements["com.apple.security.app-sandbox"], True)
            self.assertEqual(
                entitlements["com.apple.developer.networking.networkextension"],
                ["packet-tunnel-provider"],
            )
            self.assertIn(
                "VML75VY94V.ru.arvectum.proxylauncher.macos",
                entitlements["com.apple.security.application-groups"],
            )
        self.assertIs(app["com.apple.security.network.client"], True)
        self.assertIs(tunnel["com.apple.security.network.client"], True)
        self.assertIs(tunnel["com.apple.security.network.server"], True)

    def test_store_app_uses_mac_specific_shared_identity(self):
        self.assertIn("VML75VY94V.ru.arvectum.proxylauncher.macos", APP_SHARED)
        self.assertIn("ru.arvectum.proxylauncher.macos.PacketTunnel", APP_SHARED)
        self.assertIn("ru.arvectum.proxylauncher.macos.credentials", APP_SHARED)
        self.assertNotIn('group.ru.arvectum.proxylauncher.ios"', APP_SHARED)

    def test_tun2proxy_is_pinned_and_built_for_catalyst(self):
        self.assertIn('VERSION = "v0.8.3"', FETCH)
        self.assertIn('SOURCE_COMMIT = "e271de19683937f23d3f8f0eb4df0a61fc4a6e50"', FETCH)
        self.assertIn('RUST_TARGET = "aarch64-apple-ios-macabi"', FETCH)
        self.assertIn("-create-xcframework", FETCH)
        self.assertIn("disable-api-forced-exit-and-exact-host-split-dns", FETCH)
        self.assertIn("tun2proxy-split-dns.patch", FETCH)
        patch = (ROOT / "mobile" / "ios" / "Tools" / "tun2proxy-split-dns.patch").read_text(encoding="utf-8")
        self.assertIn("dns_bypass", patch)
        self.assertIn("with_bypass", patch)
        self.assertIn("RecordType::AAAA", patch)

    def test_store_release_is_0_2_19_and_uses_mac_specific_entrypoint(self):
        self.assertIn('MARKETING_VERSION: "0.2.19"', PROJECT)
        self.assertIn('CFBundleShortVersionString', APP_SHARED)
        self.assertIn("App/ArvectumProxyLauncherMacApp.swift", PROJECT)
        self.assertNotIn("../ios/App/ArvectumProxyLauncherApp.swift", PROJECT)

    def test_standard_help_menu_opens_bundled_offline_help(self):
        self.assertIn("CommandGroup(replacing: .help)", APP_ENTRY)
        self.assertIn("Справка Arvectum Proxy Launcher", APP_ENTRY)
        for phrase in (
            "Начало работы",
            "Статусы",
            "Форматы прокси",
            "Устранение неполадок",
            "О приложении и конфиденциальность",
            "© Arvectum LLC",
        ):
            self.assertIn(phrase, HELP)
        self.assertNotIn("/releases", HELP)
        self.assertNotIn("Release Notes", HELP)
        self.assertIn("https://github.com/arvectum2/proxy-launcher/issues/new", HELP)
        self.assertIn("не изменяет системный прокси через networksetup", HELP)
        self.assertIn("Telegram для macOS не подключается", HELP)
        self.assertIn("Использовать прокси", HELP)
        self.assertIn("127.0.0.1:1080", HELP)
        self.assertIn("Встроенного self-updater, обходящего App Store, в этой сборке нет.", HELP)

    def test_passive_prepare_does_not_create_or_enable_vpn_configuration(self):
        prepare = VPN.split("func prepare() async {", 1)[1].split("func connect() async throws {", 1)[0]
        connect = VPN.split("func connect() async throws {", 1)[1].split("func disconnect()", 1)[0]
        self.assertIn("loadExistingManager()", prepare)
        self.assertNotIn("loadOrCreateManager", prepare)
        self.assertIn("loadOrCreateManager()", connect)
        self.assertIn("manager.isEnabled = true", VPN)

    def test_rejected_and_already_uploaded_build_numbers_are_advanced(self):
        self.assertIn('CURRENT_PROJECT_VERSION: "8"', PROJECT)

    def test_exclusion_rows_are_visibly_deletable_and_bulk_clear_is_confirmed(self):
        content = (ROOT / "mobile" / "ios" / "App" / "ContentView.swift").read_text(encoding="utf-8")
        exclusion_view = content.split("struct ExclusionsView: View {", 1)[1].split("struct ApplicationExclusionsView: View {", 1)[0]
        self.assertIn('Button(role: .destructive)', exclusion_view)
        self.assertIn('entries.removeAll { $0 == host }', exclusion_view)
        self.assertIn('.accessibilityLabel("Удалить исключение \(host)")', exclusion_view)
        self.assertIn('.onDelete { entries.remove(atOffsets: $0) }', exclusion_view)
        self.assertIn('Button("Очистить все", role: .destructive)', exclusion_view)
        self.assertIn('confirmClearAll = true', exclusion_view)
        self.assertIn('.confirmationDialog(', exclusion_view)
        self.assertIn('isPresented: $confirmClearAll', exclusion_view)
        self.assertIn('entries.removeAll()', exclusion_view)
        self.assertIn('input = ', exclusion_view)
        self.assertIn('await model.saveExclusions(entries)', exclusion_view)
        self.assertIn('Button("Отмена") { dismiss() }', exclusion_view)

    def test_gosuslugi_site_dependency_gu_st_is_direct_bypassed(self):
        policy = (ROOT / "mobile" / "ios" / "SharedCore" / "SiteExclusionPolicy.swift").read_text(encoding="utf-8")
        tunnel = (ROOT / "mobile" / "ios" / "PacketTunnel" / "PacketTunnelProvider.swift").read_text(encoding="utf-8")
        self.assertIn('"gosuslugi.ru": ["gu-st.ru"]', policy)
        self.assertIn('let dependencies = requiredSiteHosts[apex] ?? []', policy)
        self.assertIn('return Array(Set([normalized, alias] + dependencies)).sorted()', policy)
        self.assertIn('for host in candidateHosts', tunnel)
        self.assertIn('domainMappings.insert("\(host)=\(address)")', tunnel)
        self.assertIn('addresses.insert(address)', tunnel)

    def test_www_alias_gets_real_dns_and_same_excluded_route_as_parent(self):
        policy = (ROOT / "mobile" / "ios" / "SharedCore" / "SiteExclusionPolicy.swift").read_text(encoding="utf-8")
        tunnel = (ROOT / "mobile" / "ios" / "PacketTunnel" / "PacketTunnelProvider.swift").read_text(encoding="utf-8")
        self.assertIn("static func routingHosts(for normalized: String)", policy)
        self.assertIn('alias = "www." + normalized', policy)
        self.assertIn('normalized.hasPrefix("www.")', policy)
        self.assertIn("inet_pton(AF_INET", policy)
        self.assertIn("inet_pton(AF_INET6", policy)
        self.assertIn("SiteExclusionPolicy.routingHosts(for: entry)", tunnel)
        self.assertIn('host == entry', tunnel)
        self.assertIn('guard let aliasAddresses = try? resolveHost(host) else { continue }', tunnel)
        self.assertIn('domainMappings.insert("\(host)=\(address)")', tunnel)
        self.assertIn('addresses.insert(address)', tunnel)
        self.assertIn("networkSettings(excludedAddresses: exclusions.addresses)", tunnel)

    def test_native_dns_bypass_uses_same_real_ips_as_tunnel_excluded_routes(self):
        tunnel = (ROOT / "mobile" / "ios" / "PacketTunnel" / "PacketTunnelProvider.swift").read_text(encoding="utf-8")
        self.assertIn("networkSettings(excludedAddresses: exclusions.addresses)", tunnel)
        self.assertIn("dnsBypassFlags = exclusions.dnsBypass", tunnel)
        self.assertIn("--dns virtual", tunnel)
        self.assertIn("--dns-bypass", tunnel)
        self.assertIn("domainMappings.insert", tunnel)
        self.assertIn("if !resolved.contains(host)", tunnel)
        self.assertIn("for address in try resolveHost(prepared.storedProfile.host)", tunnel)

    def test_store_export_uses_managed_installer_identity_without_cloud_signing(self):
        self.assertIn("appstore-installer.env", EXPORT)
        self.assertIn("ASC_INSTALLER_CERT_SHA1", EXPORT)
        self.assertIn("ASC_INSTALLER_KEYCHAIN", EXPORT)
        self.assertIn("ASC_INSTALLER_KEYCHAIN_PASS_FILE", EXPORT)
        self.assertIn("security unlock-keychain", EXPORT)
        self.assertIn("productbuild", EXPORT)
        self.assertIn("--component", EXPORT)
        self.assertIn("--keychain", EXPORT)
        self.assertIn("codesign --verify --deep --strict", EXPORT)
        self.assertIn("pkgutil --check-signature", EXPORT)
        self.assertNotIn("-allowProvisioningUpdates", EXPORT)
        self.assertNotIn("-authenticationKeyPath", EXPORT)
        self.assertNotIn("xcodebuild -exportArchive", EXPORT)

    def test_installer_rotation_exports_legacy_pkcs12_for_macos_security_import(self):
        self.assertIn("openssl pkcs12 -export -legacy", ROTATE)

    def test_store_tooling_prefers_current_xcode_27(self):
        self.assertIn("/Applications/Xcode-27.0.0.app", PROVISIONING)
        self.assertIn('Path("/Applications/Xcode-27.0.0.app/Contents/Developer")', FETCH)

    def test_store_lane_is_arm64_only(self):
        self.assertIn("ARCHS: arm64", PROJECT)
        self.assertIn('RUST_TARGET = "aarch64-apple-ios-macabi"', FETCH)

    def test_primary_connection_control_is_large_accessible_and_responsive(self):
        content = (ROOT / "mobile" / "ios" / "App" / "ContentView.swift").read_text(encoding="utf-8")
        self.assertIn('Text(primaryActionTitle)', content)
        self.assertIn('.frame(maxWidth: .infinity)', content)
        self.assertIn('.frame(height: 80)', content)
        self.assertIn('.accessibilityLabel(primaryActionTitle)', content)
        self.assertIn('.disabled(!model.vpn.canToggle)', content)
        self.assertNotIn('powerDiameter', content)
        self.assertIn('showNewProfile = true', content)
        self.assertIn('model.profiles.isEmpty', content)
        self.assertIn('if model.profiles.isEmpty && !model.vpn.isConnectedOrConnecting', content)
        self.assertIn('.clipShape(Capsule())', content)
        self.assertNotIn('SponsoredPlacement', content)
        self.assertIn('#if !targetEnvironment(macCatalyst)\n                    settingsButton("Автоматизация приложений"', content)

    def test_mac_dashboard_matches_card_heights_and_stacks_on_narrow_windows(self):
        content = (ROOT / "mobile" / "ios" / "App" / "ContentView.swift").read_text(encoding="utf-8")
        self.assertIn("private struct EqualHeightDashboardLayout: Layout", content)
        self.assertIn("geometry.size.width >= 820", content)
        self.assertIn("EqualHeightDashboardLayout(spacing: 18)", content)
        self.assertIn("connectionCard\n                                activeProfileCard", content)
        self.assertIn("} else {\n                            connectionCard\n                            activeProfileCard", content)
        self.assertIn("let tallest = subviews.map", content)
        self.assertIn("height: bounds.height", content)
        self.assertIn(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)", content)
        self.assertIn(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)", content)
        self.assertIn("VStack(alignment: .leading, spacing: 5)", content)
        self.assertIn(".frame(minWidth: 760, minHeight: 440)", content)
        self.assertIn(".lineLimit(1)\n                                .minimumScaleFactor(0.8)", content)

    def test_store_target_reuses_packet_tunnel_not_networksetup(self):
        self.assertIn("../ios/PacketTunnel", PROJECT)
        self.assertNotIn("macos_backend.py", PROJECT)
        self.assertNotIn("networksetup", PROJECT)


if __name__ == "__main__":
    unittest.main()
