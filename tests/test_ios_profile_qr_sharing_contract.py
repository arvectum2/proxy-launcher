"""Credential-bearing QR shares are bounded, explicit, local and interoperable."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile" / "ios"
read = lambda path: (IOS / path).read_text(encoding="utf-8")


class IOSProfileQRSharingContract(unittest.TestCase):
    def test_every_visible_profile_has_user_initiated_share_button(self):
        row = read("App/ProfileLibraryRowView.swift")
        screen = read("App/ProfilesScreenView.swift")
        self.assertIn("let onShare: () -> Void", row)
        self.assertIn('Button(action: onShare)', row)
        self.assertIn('accessibilityIdentifier("profiles.share.', row)
        self.assertIn("if !bulkMode {", row)
        self.assertIn("onShare: { sharingProfile = profile }", screen)
        self.assertIn("ProfileShareView(profile: profile)", screen)

    def test_secrets_read_only_after_share_and_qr_never_logged(self):
        model = read("App/AppViewModel.swift")
        view = read("App/ProfileShareView.swift")
        start = model.index("    func shareLink(for profile:")
        end = model.index("    /// Export is all-or-nothing:", start)
        method = model[start:end]
        self.assertIn("store.password(for: profile.id)", method)
        self.assertIn("store.profile(id: profile.id)", method)
        self.assertNotIn("print(", method)
        self.assertIn(".onAppear(perform: prepare)", view)
        self.assertIn("model.shareLink(for: profile)", view)
        self.assertIn("CIFilter.qrCodeGenerator()", view)
        self.assertIn("UIActivityViewController(activityItems: items", view)
        self.assertIn('accessibilityIdentifier("profiles.share.qrImage")', view)
        self.assertIn("может содержать логин и пароль", view)
        for forbidden in ("UserDefaults", "URLSession", "pasteboard", "UIPasteboard", "print("):
            self.assertNotIn(forbidden, view)

    def test_bounded_versioned_codec_and_both_import_paths(self):
        codec = read("SharedCore/ProxyShare.swift")
        importer = read("SharedCore/ProxyImport.swift")
        scanner = read("App/ProxyImportView.swift")
        content = read("App/ContentView.swift")
        self.assertIn('static let prefix = "apl1."', codec)
        self.assertIn("maxLinkBytes = 1_400", codec)
        self.assertIn("URLQueryItem(name: \"data\", value: payload)", codec)
        self.assertIn("case .auto", read("SharedCore/ProxyModel.swift"))
        self.assertIn("if clean.hasPrefix(ProxyShare.prefix)", importer)
        self.assertIn("try ProxyShare.decode(clean)", importer)
        self.assertIn('url.scheme?.lowercased() == "arvectum-proxy"', scanner)
        self.assertIn("try ProxyImport.fromDeepLink(url)", scanner)
        self.assertIn(".onOpenURL { url in", content)

    def test_untranslated_nonrussian_copy_falls_back_to_english(self):
        ux = read("App/ProfileShareUX.swift")
        self.assertIn("let language = AppL10n.effectiveLanguage", ux)
        self.assertIn('if language == "ru" { return key }', ux)
        self.assertIn("translations[language]?[key] ?? english[key]", ux)
        self.assertIn("Native editorial review of all", ux)


if __name__ == "__main__":
    unittest.main()
