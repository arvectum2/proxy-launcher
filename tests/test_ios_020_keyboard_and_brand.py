"""Targeted contract: all iOS text entry surfaces must have a dismiss action."""
from pathlib import Path
import unittest
APP=Path(__file__).resolve().parents[1]/'mobile/ios/App'
class KeyboardAndBrand(unittest.TestCase):
    def test_unified_brand_and_taller_native_creative(self):
        s=(APP/'ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('Text("Arvectum Proxy Launcher")',s)
        self.assertIn('Brand.symbol',s)
        self.assertIn('let equalAdHeight = min(236.0, floor(roomForAds / visibleAdSlots))',s)
        self.assertIn('maxAdHeight: inlineCreativeMax',s)
        self.assertIn('.frame(height: equalAdHeight, alignment: .top)',s)
        self.assertIn('homeNativeAdController.load()',s)
        self.assertIn('controller: homeNativeAdController',s)
        self.assertIn('roomForAds',s)
        self.assertIn('let visibleAdSlots: CGFloat = geometry.size.height >= 650 ? 2 : 1',s)
        home=s.split('private var homeConnectControl: some View {')[1].split('private var homeProfileControl:')[0]
        self.assertNotIn('stop.circle.fill',home)
        self.assertNotIn('arrow.right.circle.fill',home)
        self.assertIn('if homeConnectionIsTransitioning {',home)
        self.assertIn('.frame(height: 70)',home)
    def test_keyboard_swipe_for_every_input_screen_without_done_button(self):
        s=(APP/'KeyboardDismissSupport.swift').read_text(encoding='utf-8')
        self.assertIn('DragGesture(minimumDistance: 25)',s)
        self.assertIn('value.translation.height < -35',s)
        self.assertIn('resignFirstResponder',s)
        self.assertIn('scrollDismissesKeyboard(.immediately)',s)
        self.assertNotIn('ToolbarItemGroup(placement: .keyboard)',s)
        self.assertNotIn('keyboard.chevron.compact.down',s)
        for name in ['ProfileEditorView.swift','ProxyImportView.swift','ProfileBackupView.swift','ExclusionsView.swift']:
            self.assertIn('.keyboardDismissOnSwipeUp()', (APP/name).read_text(encoding='utf-8'),name)
    def test_main_profile_search_closes_on_upward_swipe(self):
        home=(APP/'ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('.focused($profileSearchFocused)',home)
        self.assertIn('profileSearchFocused = false',home)
        self.assertNotIn('"keyboard.dismiss.search"',home)
        self.assertIn('.keyboardDismissOnSwipeUp()',home)
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
