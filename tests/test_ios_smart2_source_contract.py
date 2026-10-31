"""Safeguards for on-device, opt-in Smart Exclusions graph integration."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "mobile" / "ios"

class IOSSmartExclusionSourceContract(unittest.TestCase):
    def test_scans_cannot_implicitly_approve_cross_site_hosts(self):
        core = (ROOT / 'SharedCore' / 'SmartExclusionGraph.swift').read_text(encoding='utf-8')
        scanner = (ROOT / 'SharedCore' / 'SiteDependencyDiscovery.swift').read_text(encoding='utf-8')
        self.assertIn('decision: .pending', core)
        self.assertIn('Self.validChild($0, for: parent)', core)
        self.assertIn('activeParents.contains($0.parent)', core)
        self.assertIn('Return display-only hints', scanner)
        self.assertIn('host != apex && !host.hasSuffix("." + apex)', scanner)

    def test_persisted_derived_rules_require_explicit_user_approval(self):
        store = (ROOT / 'Shared' / 'ProfileStore.swift').read_text(encoding='utf-8')
        vm = (ROOT / 'App' / 'AppViewModel.swift').read_text(encoding='utf-8')
        ui = (ROOT / 'App' / 'ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('smartGraph.effective(manual: manualSiteExclusions)', store)
        self.assertIn('try store.saveSmartExclusions(manual: previousManual, graph: previousGraph)', vm)
        self.assertIn('restoreAfterFailedExclusionsUpdate', vm)
        self.assertIn('var next = graph', ui)
        self.assertIn('try next.set(.approved', ui)
        self.assertIn('Общий IP-адрес может обслуживать', ui)
        self.assertIn('Отменить последнее изменение', ui)

if __name__ == '__main__':
    unittest.main()
