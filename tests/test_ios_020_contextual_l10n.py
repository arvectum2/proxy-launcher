"""New 0.2 feature texts must be genuinely localized in ALL 50 languages."""
import re
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from ios_020_locale_audit import read_strings,analyze,format_error
RES=ROOT/'mobile/ios/Resources'
APP=ROOT/'mobile/ios/App'

class IOS020ContextualLocalization(unittest.TestCase):
    def test_import_preview_not_confused_with_proxy_connectivity_check(self):
        english,_=read_strings(RES/'en.lproj/ProxyImport.strings')
        base,_=read_strings(RES/'en.lproj/Localizable.strings')
        self.assertEqual(english['Проверить'],'Preview')
        self.assertNotEqual(english['Проверить'],base.get('Проверить'))
        for lang in ('es','fr','de','ar','he','fa'):
            table,_=read_strings(RES/f'{lang}.lproj/ProxyImport.strings')
            self.assertTrue(table['Проверить'].strip(),lang)
        lang=(APP/'AppLocalization.swift').read_text(encoding='utf8')
        self.assertIn('static func tr(_ key: String, table: String)',lang)
        self.assertIn('table: "ProxyImport"',(APP/'ProxyImportUX.swift').read_text(encoding='utf8'))
        self.assertIn('table: "SmartExclusions"',(APP/'SmartExclusionsUX.swift').read_text(encoding='utf8'))

    def test_shortcuts_help_uses_chosen_app_language(self):
        s=(APP/'QuickActionsHelpView.swift').read_text(encoding='utf8')
        self.assertIn('let value = AppL10n.tr(ru)',s)
        self.assertIn('table: "QuickActions"',s)
        for lang in ('ar','ha','ja','de','fr','pt-PT','zh-Hant'):
            d,_=read_strings(RES/f'{lang}.lproj/ProfileManagement.strings')
            self.assertTrue(d['Быстрые команды VPN'])

    def test_no_primary_school_mistranslation_and_no_legal_proxies(self):
        invalid={
            'de':['Grundschule'], 'nl':['primair onderwijs'],
            'fr':['primaire','mandataire'], 'ar':['الابتدائية'],
            'da':['fuldmagt','fuldmagter'], 'sv':['fullmakt','fullmakter'],
            'ha':['firamare','wakili'], 'it':['primarie','procura primaria'],
            'ms':['sekolah rendah'], 'th':['ประถมศึกษา'],
        }
        for lang,words in invalid.items():
            d,_=read_strings(RES/f'{lang}.lproj/ProfileManagement.strings')
            primary=d['Возвращаться к основному']+' '+d['Основной прокси']
            for word in words:
                self.assertNotIn(word.casefold(),primary.casefold(),lang)

    def test_critical_destructive_and_routing_copy_not_inverted(self):
        expected={
            ('hr','ProfileManagement','Существующие профили не перезаписываются. Совпадающие пропускаются. Перед восстановлением отключите VPN.'):'neće se prepisati',
            ('sw','ProfileManagement','Существующие профили не перезаписываются. Совпадающие пропускаются. Перед восстановлением отключите VPN.'):'hautabadilishwa',
            ('ha','SmartExclusions','VPN обходят только добавленные вручную или подтверждённые домены. Для применения сохраните изменения и переподключитесь.'):'kaɗai',
            ('ar','SmartExclusions','Общий IP-адрес может обслуживать и другие сайты. Такой обход касается всего IP, не только выбранного домена.'):'جميع الاتصالات',
            ('fr','SmartExclusions','VPN обходят только добавленные вручную или подтверждённые домены. Для применения сохраните изменения и переподключитесь.'):'reconnectez le VPN',
        }
        for (lang,table,key),snippet in expected.items():
            d,_=read_strings(RES/f'{lang}.lproj'/f'{table}.strings')
            self.assertIn(snippet,d[key])

    def test_exclusions_has_short_existing_native_title(self):
        view=(APP/'ExclusionsView.swift').read_text(encoding='utf8')
        self.assertIn('.navigationTitle("Исключения")',view)
        self.assertIn('.navigationBarTitleDisplayMode(.inline)',view)
        for lang in ('fr','am','ha','ar','he','ru'):
            loc,_=read_strings(RES/f'{lang}.lproj/Localizable.strings')
            self.assertIn('Исключения',loc,lang)
            self.assertTrue(loc['Исключения'].strip(),lang)

    def test_all_new_strings_are_complete_and_have_safe_formatting(self):
        data=analyze()
        self.assertEqual(data['count'],50)
        self.assertFalse(data['resource_errors'])
        self.assertFalse(data['unchanged_english'])
        for lang in data['locales']:
            self.assertEqual(lang['new_english'],0)
            self.assertEqual(lang['QuickActions_entries'],3)
        for lang in ('ja','ko','zh-Hans','ar','he','fa','ur'):
            d,_=read_strings(RES/f'{lang}.lproj/ProfileManagement.strings')
            for key in ('Проверено %d из %d профилей','Выбрано %d из %d'):
                self.assertIsNone(format_error(key,d[key]),(lang,key,d[key]))
                self.assertIn('%1$d',d[key])
                self.assertIn('%2$d',d[key])

if __name__=='__main__':unittest.main()
