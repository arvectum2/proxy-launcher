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
        self.assertIn('ProxyFailureReason.safeDisplay(', view)
        self.assertNotIn('errorMessage = kind == .tunnel', view)
        vpn = (IOS / "App" / "VPNController.swift").read_text(encoding="utf-8")
        self.assertIn('detail = ProxyFailureReason.safeDisplay(', vpn)
        self.assertNotIn('detail = userFacingError(error).localizedDescription', vpn)
        self.assertIn('case .unknown: return "UNKNOWN"', core)
        self.assertIn('case .http407: return "HTTP 407"', core)
        self.assertNotIn('error.localizedDescription', core)
        locales = list((IOS / "Resources").glob('*.lproj/Localizable.strings'))
        self.assertEqual(len(locales), 64)
        self.assertIn('static func safeDisplay(for error:', core)
        self.assertIn('var recoveryGuidanceKey: String', core)
        self.assertIn('enum ProxyRecoveryHint: Equatable', core)
        self.assertIn('recoveryHint: ProxyRecoveryHint?', core)
        self.assertIn('for: userFacingError(error), translate:', vpn)
        guidance_keys = (
            "Проверьте адрес и порт прокси",
            "Логин и пароль нужны только для прокси с авторизацией.",
            "Если тип подключения неизвестен, уточните его у поставщика. После заполнения нажмите «Сохранить».",
            "Следите за статусом соединения. Если подключение не удалось, проверьте адрес, порт, тип и учётные данные.",
            "iOS отключила конфигурацию VPN и не позволила включить её автоматически. Откройте Настройки → VPN и разрешите Arvectum Proxy Launcher, затем повторите подключение.",
            "Конфигурация VPN была изменена системой. Перезапустите подключение — приложение перечитает и восстановит её.",
            "iOS отклонила конфигурацию Packet Tunnel. Конфигурация была восстановлена, но системе всё ещё не удалось её запустить.",
        )
        for locale in locales:
            strings = locale.read_text(encoding="utf-8")
            self.assertIn('"недоступен"', strings)
            self.assertIn('"Недоступен"', strings)
            for key in guidance_keys:
                self.assertIn('"' + key + '"', strings, locale.name)

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
