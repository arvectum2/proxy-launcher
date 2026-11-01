"""Source-only localization release checks for all 50 iOS languages."""
import sys, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from ios_020_locale_audit import analyze, read_strings
class AllLocalesAudit(unittest.TestCase):
    def test_complete_legacy_catalogs_and_safe_placeholders(self):
        x=analyze()
        self.assertEqual((x['count'],x['old_keys']),(50,155))
        self.assertFalse(x['resource_errors'])
        for lang in x['locales']:
            self.assertEqual((lang['legacy'],lang['missing_old']),(155,0),lang['locale'])
    def test_additive_fallback_complete_and_native_short_aliases(self):
        x=analyze()
        self.assertFalse(x['unhandled_dynamic'])
        self.assertEqual(x['en_supp'],x['ru_supp'])
        for lang in x['locales']:
            self.assertEqual(lang['native_core_short'],4,lang['locale'])
        swift=(ROOT/'mobile/ios/App/AppLocalization.swift').read_text(encoding='utf-8')
        for frag in ('"Домой": "Главная"','"Тема": "Тема оформления"','"Язык": "Язык приложения"','"Автоматизация": "Автоматизация приложений"'):
            self.assertIn(frag,swift)
        self.assertIn('legacyLabelAliases[key]',swift)
    def test_onboarding_backup_and_RTL_host(self):
        ru,_=read_strings(ROOT/'mobile/ios/Resources/ru.lproj/Localizable.strings')
        guide=[v for k,v in ru.items() if k.startswith('На вкладке «Главная»')]
        self.assertEqual(len(guide),1)
        self.assertIn('«Домой»',guide[0])
        for lang,expected in [('ru','Закрыть'),('en','Close')]:
            entries,_=read_strings(ROOT/f'mobile/ios/Resources/{lang}.lproj/ProfileManagement.strings')
            self.assertEqual(entries['Закрыть'],expected)
        content=(ROOT/'mobile/ios/App/ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('.environment(\\.layoutDirection, .leftToRight)',content)
        self.assertIn('"-aplSettingsLocaleQA"',content)
if __name__=='__main__':unittest.main()
