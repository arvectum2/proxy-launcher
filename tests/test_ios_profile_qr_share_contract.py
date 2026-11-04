"""Source privacy and importer interoperability for explicit profile QR sharing."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"
CORE = (IOS / "SharedCore" / "ProxyProfileSharing.swift").read_text()
STORE = (IOS / "App" / "AppViewModel.swift").read_text()
ROW = (IOS / "App" / "ProfileLibraryRowView.swift").read_text()
LIST = (IOS / "App" / "ProfilesScreenView.swift").read_text()
SHEET = (IOS / "App" / "ProxyShareView.swift").read_text()
RECEIVE = (IOS / "App" / "ProxyImportView.swift").read_text()
IMPORT = (IOS / "SharedCore" / "ProxyImport.swift").read_text()


class ProfileQRSharingContract(unittest.TestCase):
    def test_explicit_consent_gate_before_keychain_read(self):
        self.assertIn('Button { onShare(profile) }', ROW)
        self.assertIn('profiles.share.', ROW)
        self.assertIn('get: { shareCandidate != nil }', LIST)
        self.assertIn('Button(ProxyShareUX.text("Показать QR-код"))', LIST)
        self.assertIn('let link = try model.shareProxyLink(for: candidate)', LIST)
        self.assertLess(LIST.index('Button(ProxyShareUX.text("Показать QR-код"))'),
                        LIST.index('model.shareProxyLink(for: candidate)'))
        self.assertIn('store.password(for: profile.id)', STORE)
        self.assertIn('QR-код содержит адрес прокси, логин и пароль.', LIST)
        self.assertIn('sharedProfile = nil', LIST)

    def test_deep_link_is_the_existing_registered_import_type(self):
        self.assertIn('link.scheme = "arvectum-proxy"', CORE)
        self.assertIn('link.host = "import"', CORE)
        self.assertIn('ProxyImport.fromDeepLink(url)', CORE)
        self.assertIn('ProxyProfileSharing.scannedSource(code)', RECEIVE)
        self.assertIn('source = try ProxyProfileSharing.scannedSource(code)', RECEIVE)
        self.assertIn('url.user ?? ""', IMPORT)
        self.assertIn('url.password ?? ""', IMPORT)
        self.assertNotIn('url.password?.removingPercentEncoding', IMPORT)
        self.assertIn('importProfiles()', RECEIVE)

    def test_share_image_contains_quiet_zone_and_uses_apple_share_sheet(self):
        self.assertIn('CIFilter.qrCodeGenerator()', SHEET)
        self.assertIn('let margin: CGFloat = 4 * scale', SHEET)
        self.assertIn('UIColor.white.setFill()', SHEET)
        self.assertIn('UIActivityViewController(activityItems: items', SHEET)
        self.assertIn('items: [item.qrImage, item.link.absoluteString]', SHEET)
        for code in ("UIPasteboard", "UserDefaults", "store.save(", "print(",
                     "Logger(", "TelemetryStore", "startVPNTunnel("):
            self.assertNotIn(code, SHEET)

    def test_all_64_existing_locale_catalogs_unmodified(self):
        from sys import path
        path.insert(0, str(ROOT / "scripts"))
        from ios_020_locale_audit import analyze
        audit = analyze()
        self.assertFalse(audit["resource_errors"])
        self.assertEqual(audit["count"], 64)
        self.assertEqual(audit["required_tables"]["ProfileManagement"], 101)
        self.assertIn("AppL10n.effectiveLanguage", SHEET)
        self.assertIn('fallback[key]', SHEET)
        self.assertIn('translated[language]?[key]', SHEET)


if __name__ == "__main__":
    unittest.main()
