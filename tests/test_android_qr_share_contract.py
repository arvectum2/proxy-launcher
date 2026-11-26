"""Source contract for QR disclosure and URI access. Device chooser tests remain separate."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "mobile/android/app/src/main"
BASE = APP / "java/ru/arvectum/proxylauncher"
MAIN = (BASE / "MainActivity.kt").read_text()
PROVIDER = (BASE / "importing/ProxyQrShareProvider.kt").read_text()

class ShareContract(unittest.TestCase):
    def test_second_consent(self):
        consent = MAIN.split("private fun confirmQrShare(",1)[1].split("private fun shareSavedQr(",1)[0]
        share = MAIN.split("private fun shareSavedQr(",1)[1].split("private fun showProfileEditor(",1)[0]
        self.assertIn("apl_qr_share_warning", consent)
        self.assertIn("FLAG_SECURE", consent)
        self.assertNotIn("store.loadProfile", consent)
        self.assertLess(consent.index("setPositiveButton"),consent.index("shareSavedQr(profileId)"))
        self.assertLess(share.index("!canExportQr(profileId)"),share.index("store.loadProfile(profileId)"))
        self.assertIn("ProxyQrShareProvider.prepare(this, rendered)",share)
        self.assertIn("startActivity(chooser)",share)
        self.assertIn("bitmap?.recycle()",share)
        self.assertIn("ProxyQrShareProvider.revokeCurrent(this)",share)

    def test_nonexported_readonly_provider(self):
        ns = "{http://schemas.android.com/apk/res/android}"
        root = ET.parse(APP / "AndroidManifest.xml").getroot()
        provider = next(p for p in root.findall("application/provider") if p.get(ns+"name") == ".importing.ProxyQrShareProvider")
        self.assertEqual(provider.get(ns+"exported"),"false")
        self.assertEqual(provider.get(ns+"grantUriPermissions"),"true")
        self.assertEqual(provider.get(ns+"authorities"),"${applicationId}.qrshare")
        self.assertIn('if (mode != "r") throw FileNotFoundException()',PROVIDER)
        self.assertIn("MODE_READ_ONLY",PROVIDER)
        self.assertIn("store.readInto(payloadToken, offset, size, data)",PROVIDER)
        self.assertIn("revokeUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)",PROVIDER)
        self.assertIn("ExpiringQrShare.TTL_MS",PROVIDER)
        self.assertNotIn("FLAG_GRANT_WRITE_URI_PERMISSION",PROVIDER)
        self.assertNotIn("FLAG_GRANT_PERSISTABLE_URI_PERMISSION",PROVIDER)
        for forbidden in ("FileOutputStream","cacheDir","MediaStore","ClipboardManager","EXTRA_TEXT","Log."):
            self.assertNotIn(forbidden,PROVIDER)

    def test_chooser_and_localizations(self):
        for fragment in ("Intent.ACTION_SEND",'type = "image/png"',"Intent.EXTRA_STREAM","ClipData.Item(uri)","Intent.createChooser"):
            self.assertIn(fragment,PROVIDER)
        dirs = [p for p in (APP / "res").glob("values*") if (p / "strings.xml").is_file()]
        self.assertGreaterEqual(len(dirs),40)
        for d in dirs:
            root = ET.parse(d / "qr_share_strings.xml").getroot()
            self.assertEqual({x.get("name") for x in root},{"apl_qr_share_send","apl_qr_share_warning"})
            self.assertTrue(all(x.text and x.text.strip() for x in root))

if __name__ == "__main__": unittest.main()
