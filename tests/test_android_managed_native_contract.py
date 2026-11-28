from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]/'mobile/android/tools/managed-acceptance'
NS='{http://schemas.android.com/apk/res/android}'

class ManagedNativeFixtureContract(unittest.TestCase):
    def test_default_fixture_has_no_network_permission_or_native_service(self):
        root=ET.parse(ROOT/'AndroidManifest.xml').getroot()
        self.assertNotIn('android.permission.INTERNET',[n.get(NS+'name') for n in root.findall('uses-permission')])
        self.assertNotIn('.NativeFixtureService',[n.get(NS+'name') for n in root.findall('application/service')])
        self.assertNotIn('.NativeProbe',[n.get(NS+'name') for n in root.findall('instrumentation')])
    def test_native_fixture_is_local_only_and_digest_verified(self):
        build=(ROOT/'build.py').read_text()
        source=(ROOT/'NativeProbe.kt').read_text()
        self.assertIn('hashlib.sha256(source.read_bytes()).hexdigest()==sys.argv[3]',build)
        self.assertIn('lib/arm64-v8a/libtun2proxy.so',build)
        self.assertIn('.addRoute("192.0.2.17",32)',source)
        self.assertEqual(source.count('.addRoute('),1)
        self.assertNotIn('.addDnsServer(',source)
        self.assertIn('.addAllowedApplication("ru.arvectum.apl.acceptance.client")',source)
        self.assertIn('clientUid!=android.os.Process.myUid()',source)
        self.assertIn('InetAddress.getByName("127.0.0.1")',source)
        client=(ROOT/'NativeClient.java').read_text()
        self.assertIn('cm.getActiveNetwork()',client)
        self.assertIn('TRANSPORT_VPN',client)
        self.assertIn('if(vpn==null) throw',client)
        self.assertIn('android:permission="ru.arvectum.apl.acceptance.FIXTURE"',(ROOT/'NativeClientManifest.xml').read_text())
        self.assertIn("ns+'protectionLevel':'signature'",build)
        self.assertIn('VpnService.prepare(a)',source)
        self.assertNotIn('setAlwaysOnVpnPackage',source)
        self.assertIn('NativeFixtureService.revoked.await',source)
        self.assertNotIn('VpnService.prepare(c)',source)
        self.assertIn('NativeFixtureService.exited.await',source)
        self.assertIn('NativeFixtureService.engineResult.get()==0',source)
        self.assertIn('NativeFixtureService.stopResult.get()==0',source)

if __name__=='__main__': unittest.main()
