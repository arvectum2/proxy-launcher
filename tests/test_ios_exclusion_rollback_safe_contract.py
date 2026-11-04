"""Fail-closed exclusion rollback/alert UI: no untrusted NSError disclosure."""
from pathlib import Path
import unittest

IOS = Path(__file__).resolve().parents[1] / "mobile/ios"
APP = (IOS / "App/AppViewModel.swift").read_text()
UX = (IOS / "App/SiteExclusionSaveUX.swift").read_text()
MODEL = (IOS / "SharedCore/SiteExclusionSaveFailure.swift").read_text()
LOCALES = IOS / "Resources"

class ExclusionRollbackSafetyContract(unittest.TestCase):
    def setUp(self):
        self.save = APP.split("func saveExclusions(", 1)[1].split("func toggleVPN()", 1)[0]

    def test_no_untrusted_error_descriptions_in_rollback_or_save(self):
        self.assertNotIn("error.localizedDescription", self.save)
        self.assertNotIn("error.localizedDescription", UX)
        self.assertNotIn("localizedDescription", UX)
        self.assertNotIn("print(", UX)
        self.assertIn("SiteExclusionSaveUX.failed(error)", self.save)
        self.assertIn("SiteExclusionSaveUX.rollbackFailed()", self.save)
        self.assertIn("SiteExclusionSaveUX.reconnectNeeded(error)", self.save)

    def test_transaction_rollback_order_and_connection_behavior_preserved(self):
        ordered = [
            "try store.saveSmartExclusions(manual: manual, graph: nextGraph)",
            "try await vpn.reconnectIfActive()",
            "try store.saveSmartExclusions(manual: previousManual, graph: previousGraph)",
            "exclusions = store.siteExclusions",
            "manualExclusions = previousManual",
            "smartGraph = previousGraph",
            "try await vpn.restoreAfterFailedExclusionsUpdate()",
            "throw activationError",
        ]
        positions = [self.save.index(s) for s in ordered]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("let previouslyActive = vpn.isConnectedOrConnecting", self.save)
        self.assertIn("if previouslyActive", self.save)

    def test_known_graph_and_rollback_alerts_have_64_localizations(self):
        keys = {
            "SmartExclusions": [
                "Некорректный домен сайта",
                "Связанный домен не принадлежит сайту",
                "Превышен безопасный предел связанных доменов",
            ],
            "ProfileManagement": [
                "VPN: не удалось восстановить прежние исключения.",
                "Прежние исключения восстановлены, но VPN нужно подключить заново:",
            ],
        }
        for table, phrases in keys.items():
            files = sorted(LOCALES.glob("*.lproj/" + table + ".strings"))
            self.assertEqual(len(files), 64)
            for file in files:
                content = file.read_text()
                for key in phrases:
                    with self.subTest(file=file.name, language=file.parent.name, key=key):
                        self.assertIn('"' + key + '" = ', content)

    def test_typed_classifier_and_safe_codes_only(self):
        self.assertIn("enum SiteExclusionSaveFailure: Equatable", MODEL)
        self.assertIn("if let graph = error as? SmartGraphError", MODEL)
        self.assertIn("if let invalid = error as? SiteExclusionError", MODEL)
        self.assertIn("ProxyFailureReason.classify(error).code", UX)
        self.assertIn('table: "ProfileManagement"', UX)
        self.assertIn('table: "SmartExclusions"', UX)
        self.assertNotIn("NSError(", MODEL)
        self.assertNotIn("error.localizedDescription", MODEL)


if __name__ == "__main__":
    unittest.main()
