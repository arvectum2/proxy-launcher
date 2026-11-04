"""Smart4 route explanations are localized, read-only and accessible."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile" / "ios"
VIEW = (IOS / "App" / "ExclusionsView.swift").read_text(encoding="utf-8")


class Smart4RouteExplainerUIContract(unittest.TestCase):
    def test_manual_and_linked_rows_have_accessible_explain_action(self):
        self.assertEqual(VIEW.count('.accessibilityIdentifier("exclusions.routeExplain."'), 2)
        self.assertEqual(VIEW.count('Button { explainingHost ='), 2)
        self.assertIn('.accessibilityLabel(SmartExclusionsUX.text("Подробнее о правилах обхода") + " " + host)', VIEW)
        self.assertIn('.accessibilityLabel(SmartExclusionsUX.text("Подробнее о правилах обхода") + " " + edge.host)', VIEW)

    def test_preview_uses_pure_smart4_without_mutating_real_tunnel(self):
        start = VIEW.index("    private func routeExplanation(for host: String) -> String {")
        end = VIEW.index("    private func graphEdgeRow", start)
        explanation = VIEW[start:end]
        self.assertIn("SmartFlowRoutingPolicy(manual: entries, graph: graph)", explanation)
        self.assertIn("policy?.explain(host: host, resolvedIP: nil).reason", explanation)
        self.assertIn('case .manualExclusion:', explanation)
        self.assertIn('case .approvedDependency:', explanation)
        self.assertIn('case .noMatchingPermission:', explanation)
        self.assertIn('case .unverifiedHost:', explanation)
        self.assertIn('Изменения вступят в силу после сохранения и переподключения VPN.', explanation)
        for forbidden in ("saveExclusions", "manager.startVPNTunnel", "PacketTunnelProvider", "Keychain",
                          "record", "logger", "analytics", "password(for:"):
            self.assertNotIn(forbidden, explanation)

    def test_all_existing_text_keys_have_64_localized_catalog_entries(self):
        keys = [
            "Добавлено вручную",
            "Прямой",
            "Обход VPN — только для разрешённых доменов.",
            "Общий IP-адрес может обслуживать и другие сайты. Такой обход касается всего IP, не только выбранного домена.",
            "Изменения вступят в силу после сохранения и переподключения VPN.",
            "Подробнее о правилах обхода",
        ]
        localizations = sorted((IOS / "Resources").glob("*.lproj/SmartExclusions.strings"))
        self.assertEqual(len(localizations), 64)
        for locale in localizations:
            text = locale.read_text(encoding="utf-8")
            for key in keys:
                self.assertIn('"' + key + '"', text, f"Missing {key!r}: {locale.parent.name}")


if __name__ == "__main__":
    unittest.main()
