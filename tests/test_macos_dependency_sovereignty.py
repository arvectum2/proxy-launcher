import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
AUDIT = (ROOT / 'docs' / 'APL_IP_002_MAC_MACOS_STACK_DEPENDENCY_SOVEREIGNTY_AUDIT.md').read_text(encoding='utf-8')

class MacOSSovereigntyAuditContractTests(unittest.TestCase):
    def test_system_and_build_dependencies_are_named(self):
        for token in ('networksetup', 'LaunchAgents', 'hdiutil', 'GitHub macOS 15', 'PyPI', 'PyInstaller'):
            self.assertIn(token, AUDIT)
    def test_foreign_platform_constraint_is_not_hidden(self):
        self.assertIn('RELEASE-TRUST DEPENDENCY RECORDED', AUDIT)
        self.assertIn('foreign platform', AUDIT)
        self.assertIn('release-only external dependency', AUDIT)
        self.assertIn('APL-MAC-008', AUDIT)
    def test_self_hosted_replacement_path_exists(self):
        self.assertIn('self-hosted', AUDIT)
        self.assertIn('controlled mirrors', AUDIT)

if __name__ == '__main__': unittest.main()
