"""Regression: modular screens must keep one model and support accessibility text sizes."""
from pathlib import Path
import unittest
APP=Path(__file__).resolve().parents[1]/'mobile/ios/App'

class ModularAccessibility(unittest.TestCase):
    def test_theme_navigation_and_desktop_layout_extracted(self):
        main=(APP/'ContentView.swift').read_text(encoding='utf8')
        brand=(APP/'BrandTheme.swift').read_text(encoding='utf8')
        navigation=(APP/'AppDestination.swift').read_text(encoding='utf8')
        layout=(APP/'EqualHeightDashboardLayout.swift').read_text(encoding='utf8')
        self.assertNotIn('enum Brand {',main)
        self.assertNotIn('enum AppDestination:',main)
        self.assertNotIn('struct EqualHeightDashboardLayout: Layout',main)
        self.assertNotIn('PrimaryBrandButtonStyle',main)
        self.assertNotIn('SecondaryBrandButtonStyle',main)
        self.assertIn('enum Brand {',brand)
        self.assertIn('enum AppDestination: String, CaseIterable, Identifiable {',navigation)
        self.assertIn('case .home: return "house.fill"',navigation)
        self.assertIn('struct EqualHeightDashboardLayout: Layout',layout)
        self.assertIn('EqualHeightDashboardLayout(spacing: 18)',main)

    def test_compact_settings_extracted_without_copying_model_storage(self):
        source=(APP/'ContentView.swift').read_text(encoding='utf8')
        compact=(APP/'CompactSettingsView.swift').read_text(encoding='utf8')
        self.assertIn('CompactSettingsView(',source)
        self.assertIn('appearanceMode: $appearanceMode',source)
        self.assertIn('appLanguage: $appLanguage',source)
        self.assertNotIn('private var compactSettingsContent: some View',source)
        self.assertIn('@ObservedObject var model: AppViewModel',compact)
        self.assertIn('@Binding var appearanceMode: String',compact)
        self.assertIn('@Binding var showExclusions: Bool',compact)
        self.assertNotIn('ProfileStore()',compact)
        self.assertNotIn('VPNController()',compact)
        for identifier in ('settings.language','settings.theme','settings.siteExclusions',
                           'settings.quickActions','settings.returnToPrimary','settings.primaryProfile'):
            self.assertIn(identifier,compact)

    def test_dynamic_type_rows_can_grow_and_switch_to_menu(self):
        source=(APP/'CompactSettingsView.swift').read_text(encoding='utf8')
        self.assertIn('ViewThatFits(in: .vertical)',source)
        self.assertIn('ScrollView { compactSettingsContent }',source)
        self.assertIn('if dynamicTypeSize.isAccessibilitySize {',source)
        self.assertIn('themePicker.pickerStyle(.menu)',source)
        self.assertIn('themePicker.pickerStyle(.segmented)',source)
        self.assertIn('.lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)',source)
        self.assertIn('private func settingsRow<Control: View>',source)
        self.assertIn('VStack(alignment: .leading, spacing: 6)',source)
        self.assertIn('settingsRow("Тема")',source)
        self.assertIn('settingsRow("Язык")',source)
        self.assertIn('dynamicTypeSize.isAccessibilitySize ? 34 : 21',source)
        self.assertIn('.frame(minHeight: 44)',source)
        self.assertNotIn('.frame(height: 44)',source)
        self.assertIn('.accessibilityLabel(AppL10n.tr("Язык приложения"))',source)
        self.assertIn('.accessibilityHint(AppL10n.tr("Выкл. — меньше переключений:',source)

    def test_activity_is_readonly_and_accessible(self):
        main=(APP/'ContentView.swift').read_text(encoding='utf8')
        activity=(APP/'ActivityScreenView.swift').read_text(encoding='utf8')
        self.assertIn('ActivityScreenView(model: model, statusColor:',main)
        self.assertIn('@ObservedObject var model: AppViewModel',activity)
        self.assertIn('private var statusControls: some View',activity)
        self.assertIn('if dynamicTypeSize.isAccessibilitySize {',activity)
        self.assertIn('refreshButton.frame(maxWidth: .infinity, alignment: .trailing)',activity)
        self.assertIn('.frame(minWidth: 44, minHeight: 44)',activity)
        self.assertIn('.accessibilityIdentifier("activity.refresh")',activity)
        self.assertIn('.accessibilityElement(children: .combine)',activity)
        self.assertIn('Не удалось открыть VPN-сессию',activity)
        self.assertNotIn('ProfileStore()',activity)
        self.assertNotIn('toggleVPN()',activity)
        self.assertIn('.frame(minHeight: 46)',main)
        self.assertNotIn('.frame(height: 46)',main)

if __name__=='__main__': unittest.main()
