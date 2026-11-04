"""Portable privacy/locale gate for bounded JSON provider import on iOS."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"
PARSER = (IOS / "SharedCore/ProxyImport.swift").read_text()
STRUCTURED = (IOS / "SharedCore/ProxyImportStructured.swift").read_text()
VIEW = (IOS / "App/ProxyImportView.swift").read_text()
LOCALES = sorted((IOS / "Resources").glob("*.lproj/ProxyImport.strings"))
HELP = ('"Вставьте ссылки, IP:порт:логин:пароль или TXT/CSV/XML до 200 прокси. '
        'Тип выше применяется только к строкам без протокола."')


class JSONProviderImportContract(unittest.TestCase):
    def test_json_is_opt_in_without_breaking_ipv6_supplier_syntax(self):
        self.assertIn('clean.first == "{" || ProxyImportStructured.looksLikeJSONArray(clean)', PARSER)
        self.assertIn("ProxyImportStructured.json(clean, defaultType: fallback)", PARSER)
        self.assertIn('guard input.first == "[" else { return false }', STRUCTURED)
        self.assertIn('firstValue == "{" || firstValue == "\\"" || firstValue == "]"', STRUCTURED)

    def test_json_is_bounded_and_all_or_nothing(self):
        self.assertIn("data.count <= 256_000", STRUCTURED)
        self.assertIn("records.count <= 200", STRUCTURED)
        self.assertIn("JSONSerialization.jsonObject", STRUCTURED)
        self.assertIn("throw ProxyImportError.invalid", STRUCTURED)
        self.assertIn("ProxyImport.item(", STRUCTURED)
        self.assertIn("ProxyImport.parseLine(link", STRUCTURED)
        self.assertIn("normalized.updateValue(fieldValue, forKey: canonical) == nil", STRUCTURED)
        self.assertIn("CFBooleanGetTypeID()", STRUCTURED)

    def test_file_picker_accepts_json_and_preserves_existing_limit(self):
        self.assertIn("allowedContentTypes: [.plainText, .commaSeparatedText, .xml, .json]", VIEW)
        self.assertIn("guard data.count <= 256_000", VIEW)
        self.assertIn("ProxyImport.withoutDuplicates", VIEW)
        self.assertIn("model.rollbackImportedProfiles", VIEW)
        self.assertIn("scanAfterSave: false", VIEW)
        self.assertIn("Task { await model.scanProfiles() }", VIEW)

    def test_64_translations_declare_new_format_and_preserve_lookup_key(self):
        self.assertEqual(len(LOCALES), 64)
        for file in LOCALES:
            rows = [line for line in file.read_text().splitlines()
                    if line.startswith(HELP + " = ")]
            with self.subTest(locale=file.parent.name):
                self.assertEqual(len(rows), 1)
                key, value = rows[0].split(" = ", 1)
                self.assertEqual(key, HELP)
                self.assertIn("TXT/CSV/XML/JSON", value)
                self.assertNotIn("TXT/CSV/XML/JSON", key)

    def test_no_secret_logging_or_network_in_json_parser(self):
        json_code = STRUCTURED.split("static func json(", 1)[1].split("static func looksLikeCSV(", 1)[0]
        for forbidden in ("print(", "Logger(", "os_log(", "URLSession(",
                          "UIPasteboard", "NetworkExtension", "Keychain", "FileHandle"):
            self.assertNotIn(forbidden, json_code)


if __name__ == "__main__":
    unittest.main()
