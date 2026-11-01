"""Targeted contract: all iOS text entry surfaces must have a dismiss action."""
from pathlib import Path
import unittest
APP=Path(__file__).resolve().parents[1]/'mobile/ios/App'
class KeyboardAndBrand(unittest.TestCase):
    def test_unified_brand_and_taller_native_creative(self):
        s=(APP/'ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('Text("Arvectum Proxy Launcher")',s)
        self.assertIn('Brand.symbol',s)
        self.assertIn('height: compact ? 150 : 205',s)
        home=s.split('private var homeConnectControl: some View {')[1].split('private var homeProfileControl:')[0]
        self.assertNotIn('stop.circle.fill',home)
        self.assertNotIn('arrow.right.circle.fill',home)
        self.assertIn('if homeConnectionIsTransitioning {',home)
        self.assertIn('.frame(height: 70)',home)
    def test_keyboard_done_for_every_input_screen(self):
        s=(APP/'KeyboardDismissSupport.swift').read_text(encoding='utf-8')
        self.assertIn('ToolbarItemGroup(placement: .keyboard)',s)
        self.assertIn('resignFirstResponder',s)
        self.assertIn('keyboard.chevron.compact.down',s)
        self.assertIn('scrollDismissesKeyboard(.interactively)',s)
        for name in ['ProfileEditorView.swift','ProxyImportView.swift','ProfileBackupView.swift','ExclusionsView.swift']:
            self.assertIn('.keyboardDismissToolbar()', (APP/name).read_text(encoding='utf-8'),name)
    def test_main_profile_search_has_an_always_accessible_done_button(self):
        home=(APP/'ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('.focused($profileSearchFocused)',home)
        self.assertIn('profileSearchFocused = false',home)
        self.assertIn('"keyboard.dismiss.search"',home)
        self.assertIn('.frame(width: 44, height: 44)',home)
        self.assertIn('.submitLabel(.done)',home)
    def test_inputs_are_all_covered_and_alert_has_close_buttons(self):
        entry_files=['ContentView.swift','ProfileEditorView.swift','ProxyImportView.swift','ProfileBackupView.swift','ExclusionsView.swift']
        for name in entry_files:
            text=(APP/name).read_text(encoding='utf-8')
            self.assertTrue(any(x in text for x in ('TextField(', 'TextEditor(', 'SecureField(')))
        text=(APP/'ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('customGroupName',text)
        self.assertIn('Button(AppL10n.tr("Отмена"), role: .cancel)',text)
if __name__=='__main__':unittest.main()
