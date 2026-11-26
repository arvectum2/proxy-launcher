"""Source boundary tests, not Android UI/device acceptance."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "mobile/android/app"
BASE = APP / "src/main/java/ru/arvectum/proxylauncher"
ACTIVITY = (BASE / "MainActivity.kt").read_text()
CODEC = (BASE / "model/ProxyQrExport.kt").read_text()

class QrExportContract(unittest.TestCase):
    def test_consent_before_secret_read(self):
        consent = ACTIVITY.split("private fun confirmQrExport(",1)[1].split("private fun showQrExportFailure(",1)[0]
        display = ACTIVITY.split("private fun displaySavedQr(",1)[1].split("private fun confirmQrShare(",1)[0]
        self.assertIn("if (!canExportQr(profileId)) return", consent)
        self.assertIn("apl_qr_export_warning", consent)
        self.assertNotIn("store.loadProfile", consent)
        self.assertLess(consent.index("setPositiveButton"),consent.index("displaySavedQr(profileId)"))
        self.assertLess(display.index("if (!canExportQr(profileId)) return"),display.index("store.loadProfile(profileId)"))
        self.assertIn("FLAG_SECURE", consent)
        self.assertIn("FLAG_SECURE", display)
        for forbidden in ("ClipboardManager", "startActivity", "appendImportedProfiles", "saveProfile", "Log."):
            self.assertNotIn(forbidden, consent + display)

    def test_display_disposal(self):
        self.assertIn("qrExportDialog?.dismiss()", ACTIVITY.split("override fun onPause() {",1)[1].split("override fun onStop()",1)[0])
        self.assertIn("if (state != ProxyVpnService.STATE_DISCONNECTED) qrExportDialog?.dismiss()", ACTIVITY)
        self.assertIn("image.setImageDrawable(null)", ACTIVITY)
        self.assertIn("bitmap.recycle()", ACTIVITY)
        self.assertIn("pixels.fill(0)", ACTIVITY)
        self.assertIn("isSaveEnabled = false", ACTIVITY)

    def test_encoding_and_warning_resources(self):
        self.assertIn("MAX_PAYLOAD_BYTES = 1800", CODEC)
        self.assertIn("ProxyQrImport.parsePayload(link)", CODEC)
        self.assertIn("ErrorCorrectionLevel.M", CODEC)
        self.assertIn("EncodeHintType.MARGIN to 4", CODEC)
        dirs = [p for p in (APP / "src/main/res").glob("values*") if (p / "strings.xml").is_file()]
        self.assertGreaterEqual(len(dirs),40)
        for d in dirs:
            root = ET.parse(d / "qr_export_strings.xml").getroot()
            self.assertEqual({x.attrib["name"] for x in root},
                {"apl_qr_export_confirm","apl_qr_export_show","apl_qr_export_warning",
                 "apl_qr_export_failed","apl_qr_export_image"})
            self.assertTrue(all(x.text and x.text.strip() for x in root))

if __name__ == "__main__":
    unittest.main()
