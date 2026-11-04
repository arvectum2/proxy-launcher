"""Portable source privacy gate for bounded iOS Files proxy importer."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"
READER = (IOS / "SharedCore/ProxyImportFileReader.swift").read_text()
UI = (IOS / "App/ProxyImportView.swift").read_text()


class BoundedProxyFileImportContracts(unittest.TestCase):
    def test_never_read_entire_file_before_size_check(self):
        self.assertNotIn("Data(contentsOf: url)", UI)
        self.assertIn("ProxyImportFileReader.readUTF8(from: url)", UI)
        self.assertIn("FileHandle(forReadingFrom: url)", READER)
        self.assertIn("handle.read(upToCount: request)", READER)
        self.assertIn("private static let chunkSize = 16_384", READER)
        self.assertIn("static let maxBytes = 256_000", READER)

    def test_one_byte_overflow_detection_and_full_utf8(self):
        self.assertIn("let remaining = maxBytes - bytes.count", READER)
        self.assertIn("let request = min(chunkSize, remaining + 1)", READER)
        self.assertIn("chunk.count <= remaining", READER)
        self.assertIn("String(data: bytes, encoding: .utf8)", READER)
        self.assertIn("ProxyImportError.tooLarge", READER)
        self.assertIn("ProxyImportError.invalid", READER)

    def test_file_handle_and_security_scope_closed_on_failure(self):
        self.assertIn("defer { try? handle.close() }", READER)
        self.assertIn("guard url.isFileURL", READER)
        self.assertIn("url.startAccessingSecurityScopedResource()", UI)
        self.assertIn("defer { if access { url.stopAccessingSecurityScopedResource() } }", UI)

    def test_no_credential_or_path_logging_in_reader(self):
        executable = "\n".join(line for line in READER.splitlines()
                               if not line.lstrip().startswith("//"))
        for forbidden in ("print(", "Logger(", "os_log(", "URLSession",
                          "UIPasteboard", "Keychain", "NetworkExtension",
                          "String(describing:"):
            self.assertNotIn(forbidden, executable)
        self.assertIn("ProxyImportUX.error(caught)", UI)


if __name__ == "__main__":
    unittest.main()
