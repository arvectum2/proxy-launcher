from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
BASE=Path(__file__).resolve().parents[1]/'mobile/android/app/src/main'
SRC=BASE/'java/ru/arvectum/proxylauncher'
class ManagedDialogContract(unittest.TestCase):
    def test_dialog_remains_dormant(self):
        self.assertNotIn('ManagedReviewDialogs(', (SRC/'MainActivity.kt').read_text())
        code=(SRC/'ui/ManagedReviewDialogs.kt').read_text()
        for token in ('session.attach(ticket)','session.permits(ticket)','FLAG_SECURE','positive.isEnabled=!needsConsent','needsConsent && !consent.isChecked','session.invalidate();complete'):
            self.assertIn(token,code)
    def test_all_supported_locales_have_exact_keys_and_formats(self):
        res=BASE/'res'
        def strings(path):
            entries=ET.parse(path).getroot()
            values={s.attrib['name']:s.text or '' for s in entries}
            self.assertEqual(len(entries),len(values),str(path))
            return values
        default=strings(res/'values'/'managed_review_strings.xml')
        import re
        for directory in sorted(res.glob('values*')):
            if not (directory/'strings.xml').exists(): continue
            path=directory/'managed_review_strings.xml'
            self.assertTrue(path.is_file(),directory.name)
            actual=strings(path)
            self.assertEqual(set(actual),set(default),directory.name)
            for key,value in actual.items():
                self.assertTrue(value.strip(),(directory.name,key))
                self.assertEqual(re.findall(r'%[0-9]+\$[ds]',value),re.findall(r'%[0-9]+\$[ds]',default[key]),(directory.name,key))
            self.assertNotIn('MissingTranslation',path.read_text())
    def test_ru_en_resources_and_distinct_denials(self):
        def names(locale): return {s.attrib['name'] for s in ET.parse(BASE/'res'/locale/'managed_review_strings.xml').getroot()}
        self.assertEqual(names('values'),names('values-en'))
        self.assertTrue({'managed_vpn_busy','managed_vpn_pending','managed_followup_uncertain'}<=names('values'))
        service=(SRC/'tunnel/ProxyVpnService.kt').read_text()
        self.assertIn('ManagedReviewMessages.vpnDenied(profileGateStatus)',service)
if __name__=='__main__': unittest.main()
