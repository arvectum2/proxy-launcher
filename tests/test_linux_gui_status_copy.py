import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
TEXT = (ROOT / 'linux_gui.py').read_text(encoding='utf-8')

class LinuxGuiStatusCopyTests(unittest.TestCase):
    def test_active_status_is_networkmanager_specific(self):
        self.assertIn('NetworkManager и desktop proxy', TEXT)
        active = TEXT.split('if enabled:', 1)[1].split('if pending:', 1)[0]
        self.assertNotIn('Windows', active)

    def test_recovery_status_is_linux_specific(self):
        recovery = TEXT.split('if pending:', 1)[1].split('try:', 1)[0]
        self.assertIn('настройки NetworkManager и desktop proxy', recovery)
        self.assertNotIn('Windows', recovery)
        self.assertNotIn('Linux/Astra', recovery)
        self.assertIn('self._platform_label', recovery)

if __name__ == '__main__':
    unittest.main()
