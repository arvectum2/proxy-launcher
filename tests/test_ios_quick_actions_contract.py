"""Source and localization contract for explicit iOS App Intents quick actions."""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[1]/'mobile'/'ios'
SWIFT=(ROOT/'App'/'VPNShortcuts.swift').read_text(encoding='utf-8')
HELP=(ROOT/'App'/'QuickActionsHelpView.swift').read_text(encoding='utf-8')
CORE=(ROOT/'SharedCore'/'QuickVPNActionPolicy.swift').read_text(encoding='utf-8')

class QuickActionsContract(unittest.TestCase):
    def test_explicit_only_idempotent_actions_and_preserved_app_automation(self):
        for name in ['ConnectAPLIntent','DisconnectAPLIntent','ToggleAPLIntent','SelectedAppOpenedIntent','SelectedAppClosedIntent']:
            self.assertIn('struct '+name+': AppIntent',SWIFT)
            self.assertIn('intent: '+name+'()',SWIFT)
        for action in ['connect','disconnect','toggle']:
            self.assertIn('applyQuickAction(.'+action+')',SWIFT)
        self.assertIn('static let openAppWhenRun = false',SWIFT)
        self.assertIn('guard !explicitQuickActionInProgress',SWIFT)
        self.assertIn('try await controller.disconnectAndWait()',SWIFT)
        self.assertIn('if state == .disconnecting { return .busy }',CORE)
        self.assertIn('case .connect:',CORE)
        self.assertIn('case .disconnect:',CORE)
        self.assertIn('case .toggle:',CORE)
        self.assertIn('applySelectedAppEvent(opened:',SWIFT)

    def test_quick_action_localizations_are_separate_from_source_catalog(self):
        codes=['en','ru','ar','de','es','fa','fr','he','hi','it','ja','ko','pt-BR','pt-PT','zh-Hans','zh-Hant']
        for code in codes:
            path=ROOT/'Resources'/f'{code}.lproj'/'QuickActions.strings'
            self.assertTrue(path.is_file(),path)
            d=path.read_text(encoding='utf-8')
            self.assertEqual(sum(bool(re.match(r'^".+" = ".+";$',line)) for line in d.splitlines()),3)
            self.assertIn('"Подключить APL"',d)
            self.assertIn('"Отключить APL"',d)
            self.assertIn('"Переключить APL"',d)
        for path in (ROOT/'Resources').glob('*.lproj/Localizable.strings'):
            self.assertEqual(sum(line.startswith('"') and ' = ' in line for line in path.read_text(encoding='utf-8').splitlines()),155,path)
        self.assertIn('table: "QuickActions"',SWIFT)
        self.assertIn('for code in [AppL10n.effectiveLanguage, "en"]',HELP)

    def test_ui_opens_shortcuts_only_via_explicit_link(self):
        content=(ROOT/'App'/'ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('settings.quickActions',content)
        self.assertIn('if #available(iOS 16.0, *)',content)
        self.assertIn('QuickActionsHelpView()',content)
        self.assertIn('shortcuts://',HELP)
        self.assertIn('quickActions.openShortcuts',HELP)

if __name__=='__main__': unittest.main()
