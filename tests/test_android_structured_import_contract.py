"""Structured import source boundaries; Android device storage QA remains separate."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "mobile/android/app/src/main"
BASE = APP / "java/ru/arvectum/proxylauncher"
MAIN = (BASE / "MainActivity.kt").read_text()
STRUCTURED = (BASE / "model/ProxyStructuredImport.kt").read_text()
JSON = (BASE / "model/StructuredJsonReader.kt").read_text()

class StructuredContract(unittest.TestCase):
    def test_existing_preview_and_file_guard(self):
        editor = MAIN.split("private fun showBatchImport()",1)[1].split("private fun showSubscriptionInput()",1)[0]
        worker = MAIN.split("private fun importSelectedTextFile(",1)[1].split("private fun chooseQrImage()",1)[0]
        self.assertIn("ProxyStructuredImport.parseBatch(input.text.toString())", editor)
        self.assertIn("FLAG_SECURE", editor)
        self.assertIn("Intent.ACTION_OPEN_DOCUMENT", editor)
        for mime in ("application/json","text/csv","application/xml","text/plain"):
            self.assertIn(mime, editor)
        self.assertIn('uri.scheme != "content"',worker)
        self.assertIn("use(ProxyBatchImport::readText)?.let(ProxyStructuredImport::parseBatch)",worker)
        self.assertIn("showBatchPreview(items)",worker)
        for forbidden in ("appendImportedProfiles","connectVpn()","takePersistableUriPermission","Log."):
            self.assertNotIn(forbidden,editor+worker)

    def test_bounded_strict_xml_and_json(self):
        self.assertIn("ProxyBatchImport.MAX_BYTES",STRUCTURED)
        self.assertIn("ProxyBatchImport.MAX_ENTRIES",STRUCTURED)
        self.assertIn('contains("<!DOCTYPE", ignoreCase = true)',STRUCTURED)
        self.assertIn('contains("<!ENTITY", ignoreCase = true)',STRUCTURED)
        self.assertIn("InputSource(StringReader(clean))",STRUCTURED)
        self.assertIn("External entity forbidden",STRUCTURED)
        self.assertIn("fields.containsKey(k)",STRUCTURED)
        self.assertIn("record(false)",JSON)
        self.assertIn('canonical != "port"',JSON)
        self.assertIn("ProxyBatchImport.MAX_ENTRIES",JSON)
        self.assertNotIn("org.json",JSON)
        self.assertNotIn("ProxyStructuredImport", (BASE/"model/ProxyQrImport.kt").read_text())

    def test_file_label_resources(self):
        dirs = [p for p in (APP/"res").glob("values*") if (p/"strings.xml").is_file()]
        self.assertGreaterEqual(len(dirs),40)
        for d in dirs:
            item = ET.parse(d/"structured_import_strings.xml").getroot().find("string")
            self.assertEqual(item.attrib["name"],"apl_import_choose_file")
            self.assertTrue(item.text and item.text.strip())

if __name__ == "__main__": unittest.main()
