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
        self.assertIn('SafeConnectionAlert.forError(error)', view)
        self.assertIn('AppL10n.tr(advice.localizationKey)', view)
        connect = view.split('func toggleVPN()', 1)[1].split('#if targetEnvironment(macCatalyst)', 1)[0]
        self.assertNotIn('error.localizedDescription', connect)
        self.assertIn('approvedVPNHints.contains(nsError.localizedDescription)', core)
        self.assertIn('return Self(localizationKey: key, code: reason.code)', core)
        self.assertIn('case .unknown: return "UNKNOWN"', core)
        self.assertIn('case .http407: return "HTTP 407"', core)
        self.assertNotIn('error.localizedDescription', core)
        locales = list((IOS / "Resources").glob('*.lproj/Localizable.strings'))
        self.assertEqual(len(locales), 64)
        keys = [
            '"недоступен"',
            '"Проверьте адрес и порт прокси"',
            '"Следите за статусом соединения. Если подключение не удалось, проверьте адрес, порт, тип и учётные данные."',
            '"Конфигурация VPN была изменена системой. Перезапустите подключение — приложение перечитает и восстановит её."',
        ]
        for locale in locales:
            text = locale.read_text(encoding="utf-8")
            for key in keys:
                self.assertIn(key, text, f"{locale.name}: missing {key}")

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
