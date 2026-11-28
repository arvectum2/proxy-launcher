from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]/'mobile/android'
FIX=ROOT/'tools/managed-acceptance'

class ManagedEnabledUiFixtureContract(unittest.TestCase):
    def test_activation_is_copy_only_and_network_disabled(self):
        source=(ROOT/'app/src/main/java/ru/arvectum/proxylauncher/ui/ManagedSubscriptionController.kt').read_text()
        build=(FIX/'build-enabled-ui.py').read_text()
        self.assertIn('const val ENABLED = false',source)
        self.assertIn("shutil.copytree(src/name,out/name)",build)
        self.assertIn("controller=base/'ui/ManagedSubscriptionController.kt'",build)
        self.assertIn("const val ENABLED = true",build)
        self.assertIn("if node.get(ns+'name')=='android.permission.INTERNET':root.remove(node)",build)
        self.assertIn('fetch.cancel()',build)
        self.assertIn('managedRequest?.url == "https://example.com/apl-fixture"',build)
        self.assertIn('ru.arvectum.proxylauncher.acceptanceui',build)
        self.assertIn('hashlib.sha256(artifact.read_bytes()).hexdigest()==sys.argv[3]',build)
    def test_smoke_requires_disposable_emulator_and_never_grants_vpn(self):
        smoke=(FIX/'run-enabled-ui.py').read_text()
        self.assertIn("=='apl_enabled_ui'",smoke)
        self.assertIn("'ro.kernel.qemu'",smoke)
        self.assertIn("'ro.build.version.sdk'",smoke)
        self.assertIn("tap('Cancel')",smoke)
        self.assertIn("'ProxyVpnService' not in cmd",smoke)
        self.assertIn("node('CONFIRM').get('enabled')=='false'",smoke)
        self.assertNotIn('appops',smoke)

if __name__=='__main__': unittest.main()
