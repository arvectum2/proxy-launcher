"""Source regression checks for the 0.2 iPhone usability cleanup."""
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
APP=ROOT/'mobile/ios/App'

class UXCleanup(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.home=(APP/'ContentView.swift').read_text(encoding='utf-8')
    def test_primary_action_transition_stays_inside_stable_button(self):
        control=self.home.split('private var homeConnectControl: some View {',1)[1].split('private var homeProfileControl:',1)[0]
        self.assertIn('if homeConnectionIsTransitioning {',control)
        self.assertIn('ProgressView()',control)
        self.assertIn('stop.circle.fill',control)
        self.assertIn('.frame(width: 24, height: 24)',control)
        self.assertIn('.frame(height: 70)',control)
        self.assertNotIn('Text(AppL10n.tr(qaStatusTitle))',control)
    def test_profiles_manage_in_one_card_without_repeated_selector(self):
        s=self.home.split('private var profilesScreen: some View {',1)[1].split('private var activityScreen:',1)[0]
        self.assertNotIn('Text("Текущий профиль")',s)
        self.assertNotIn('Text(AppL10n.tr("Список прокси"))',s)
        self.assertIn('Text(AppL10n.tr("Профили"))',s)
        self.assertIn('model.selectedProfileID == profile.id',s)
        self.assertIn('.frame(minHeight: 44)',s)
        self.assertIn('showProfileBackup = true',s)
    def test_activity_settings_and_destructive_taps_are_clutter_free(self):
        s=self.home.split('private var activityScreen: some View {',1)[1].split('private var settingsScreen:',1)[0]
        self.assertNotIn('Состояние соединения и последние события',s)
        settings=self.home.split('private var compactAutomaticRoutingSettings: some View {',1)[1].split('private var profileSelectionMenu:',1)[0]
        self.assertNotIn('Text(AppL10n.tr("Выкл. — остаёмся',settings)
        self.assertIn('.accessibilityHint(AppL10n.tr("Выкл. — меньше переключений',settings)
        exclusions=(APP/'ExclusionsView.swift').read_text(encoding='utf-8')
        self.assertIn('.frame(minWidth: 44, minHeight: 44)',exclusions)
        ad=(APP/'NativeHomeAdView.swift').read_text(encoding='utf-8')
        self.assertIn('feedback.widthAnchor.constraint(equalToConstant: 44)',ad)
        self.assertIn('feedback.heightAnchor.constraint(equalToConstant: 44)',ad)
        self.assertIn('.fixedSize(horizontal: true, vertical: false)',exclusions)
        self.assertIn('"profiles.emptyState"',self.home)
        self.assertIn('"Нет прокси"',self.home)
        self.assertIn('Не удалось открыть VPN-сессию',self.home)
        backup=(APP/'ProfileBackupView.swift').read_text(encoding='utf-8')
        self.assertIn('DisclosureGroup {',backup)
        self.assertIn('backup.explanation',backup)
if __name__=='__main__':
    unittest.main()
