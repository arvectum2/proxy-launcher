"""Check safety copy, RTL and 50-language fallback for Smart Exclusions 2."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT/'mobile'/'ios'
UX = (IOS/'App'/'SmartExclusionsUX.swift').read_text(encoding='utf-8')
VIEW = (IOS/'App'/'ContentView.swift').read_text(encoding='utf-8')
SCREEN = VIEW.split('struct ExclusionsView: View {',1)[1].split('struct ApplicationExclusionsView:',1)[0]

class IOSSmartExclusionsUXLocaleTests(unittest.TestCase):
    def test_all_new_smart_copy_english_or_native_fallback(self):
        # Extract keys from top-level English mapping only, excluding priority locales.
        english = UX.split('private static let english:',1)[1].split('static func text(',1)[0]
        labels = re.findall(r'(?m)^\s*"([^"\\]+)": "([^"\\]+)"', english)
        self.assertGreaterEqual(len(labels), 26)
        for key,value in labels:
            self.assertTrue(key.strip() and value.strip())
            self.assertFalse(any('\u0400' <= c <= '\u052f' for c in value),key)
        self.assertIn('if language == "ru" { return russian }',UX)
        self.assertIn('if let translated = priority[language]?[russian]',UX)
        self.assertIn('if let fallback = english[russian]',UX)
        self.assertIn('Could not complete the operation.',UX)
        self.assertIn('SmartExclusionsUX.text(localError)',SCREEN)

    def test_priority_languages_include_rtl_and_source_catalogs_stay_intact(self):
        for lang in ['es','fr','de','pt-BR','pt-PT','it','ja','ko','zh-Hans','zh-Hant','ar','fa','he','hi']:
            self.assertIn('"'+lang+'": [',UX)
        self.assertIn('"Найти связанные домены": "חיפוש דומיינים קשורים"',UX)
        catalogs=list((IOS/'Resources').glob('*.lproj/Localizable.strings'))
        self.assertEqual(len(catalogs),50)
        for p in catalogs:
            self.assertEqual(sum(line.startswith('"') and ' = ' in line for line in p.read_text(encoding='utf-8').splitlines()),155,p)

    def test_new_buttons_have_accessibility_and_no_implicit_permissions(self):
        self.assertIn('.frame(minHeight: 44)',SCREEN)
        self.assertIn('.accessibilityLabel(SmartExclusionsUX.text("Удалить")',SCREEN)
        self.assertIn('.accessibilityLabel(SmartExclusionsUX.text("Добавить вручную")',SCREEN)
        self.assertIn('isPresented: $confirmExternal',SCREEN)
        self.assertIn('try next.set(.approved',SCREEN)

if __name__=='__main__': unittest.main()
