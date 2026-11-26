"""Source/resource boundary checks; not a substitute for Android device QA."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "mobile/android/app/src/main/res"
ACTIVITY = ROOT / "mobile/android/app/src/main/java/ru/arvectum/proxylauncher/MainActivity.kt"

class AndroidImportPreviewContract(unittest.TestCase):
    def test_all_existing_locales_have_import_labels(self):
        expected = {"apl_import_proxy_link", "apl_import_proxy_preview", "apl_import_proxy_invalid"}
        locales = [p for p in RES.glob("values*") if (p / "strings.xml").is_file()]
        self.assertGreaterEqual(len(locales), 40)
        for locale in locales:
            with self.subTest(locale=locale.name):
                resources = ET.parse(locale / "import_strings.xml").getroot()
                self.assertEqual({node.attrib["name"] for node in resources}, expected)
                self.assertTrue(all(node.text and node.text.strip() for node in resources))
                original = ET.parse(locale / "strings.xml").getroot()
                self.assertFalse(expected & {node.get("name") for node in original})

    def test_preview_only_populates_editor(self):
        text = ACTIVITY.read_text()
        preview = text.split("if (creating) {\n            titleRow.addView(brandSmallButton(getString(R.string.apl_import_proxy_link)", 1)[1].split("val primaryId =", 1)[0]
        self.assertIn("ProxyImport.parse(input.text.toString())", preview)
        self.assertIn("passwordField.setText(item.password)", preview)
        self.assertIn("FLAG_SECURE", preview)
        self.assertIn("input.text.clear()", preview)
        for forbidden in ("store.save", "requestLiveSwitch", "VpnService.prepare", "ClipboardManager", "Log."):
            self.assertNotIn(forbidden, preview)

if __name__ == "__main__":
    unittest.main()
