"""Static privacy and UI wiring regression checks for typed iOS diagnostics."""
from pathlib import Path
import unittest

IOS = Path(__file__).resolve().parents[1] / "mobile" / "ios"


class IOSProxyDiagnosticsContractTests(unittest.TestCase):
    def test_ui_uses_localized_unavailable_status_and_safe_codes(self):
        view = (IOS / "App" / "AppViewModel.swift").read_text(encoding="utf-8")
        core = (IOS / "SharedCore" / "ProxyFailureReason.swift").read_text(encoding="utf-8")
        self.assertIn('case unavailable(ProxyFailureReason)', view)
        self.assertIn('AppL10n.tr("недоступен")', view)
        self.assertIn('ProxyFailureReason.classify(error)', view)
        self.assertIn('healthScanGeneration', view)
        self.assertIn('kind == .tunnel', view)
        self.assertIn('case .unknown: return "UNKNOWN"', core)
        self.assertIn('case .http407: return "HTTP 407"', core)
        self.assertNotIn('error.localizedDescription', core)
        locales = list((IOS / "Resources").glob('*.lproj/Localizable.strings'))
        self.assertEqual(len(locales), 50)
        for locale in locales:
            self.assertIn('"недоступен"', locale.read_text(encoding="utf-8"))

    def test_probe_fails_closed_on_challenge_and_never_publishes_secrets(self):
        probe = (IOS / "Shared" / "ProxyProbe.swift").read_text(encoding="utf-8")
        self.assertIn('ProxyFailureReason.forHTTPConnectStatus(status)', probe)
        self.assertIn('ProxyDiagnosticError(.authentication)', probe)
        self.assertIn('ProbeCompletionGate', probe)
        self.assertIn('failures.append(Self.failureReason(for: error))', probe)
        self.assertNotIn('failures.append("', probe)
        self.assertNotIn('text.range(of: "Proxy-Authenticate: Digest"', probe)


if __name__ == "__main__":
    unittest.main()
