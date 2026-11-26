"""Safe source contracts for encrypted Files import/export; unittest CI compatible."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "mobile/ios/SharedCore/ProfileBackup.swift"
VIEW = ROOT / "mobile/ios/App/ProfileBackupView.swift"
TEST = ROOT / "mobile/ios/Tests/CoreTests/ProfileBackupTests.swift"


class BackupFileSafetyContracts(unittest.TestCase):
    def test_export_filename_is_fresh_per_operation_and_opaque(self):
        source = CORE.read_text()
        view = VIEW.read_text()
        self.assertIn("static func exportFilename(date: Date = Date(), identifier: UUID = UUID())", source)
        self.assertIn('format.dateFormat = "yyyyMMdd-HHmmss"', source)
        self.assertIn("identifier.uuidString.lowercased()", source)
        self.assertIn("exportFilename = ProfileBackupCodec.exportFilename()", view)
        self.assertIn("defaultFilename: exportFilename", view)
        self.assertNotIn('defaultFilename: "APL-Profiles-Encrypted"', view)

    def test_import_is_bounded_even_for_lying_file_provider(self):
        core = CORE.read_text()
        view = VIEW.read_text()
        self.assertIn("static func readEncryptedFile(at url: URL) throws -> Data", core)
        self.assertIn("let handle = try FileHandle(forReadingFrom: url)", core)
        self.assertIn("maxFileBytes + 1 - result.count", core)
        self.assertIn("guard (64...maxFileBytes).contains(result.count)", core)
        self.assertIn("encryptedData = try ProfileBackupCodec.readEncryptedFile(at: file)", view)
        self.assertNotIn("Data(contentsOf: file)", view)
        self.assertIn("file.startAccessingSecurityScopedResource()", view)

    def test_swift_checks_wire_roundtrip_exact_size_and_rejection(self):
        source = TEST.read_text()
        for name in (
            "testExportFilenamesAreUniqueAndContainNoSecret",
            "testEncryptedImportReaderIsBoundedAndPreservesCiphertext",
            "testEncryptedImportReaderAllowsExactLimitButRejectsNonFileURL",
            "testEncryptedImportReaderRejectsOversizedAndTruncatedFiles",
        ):
            self.assertIn(name, source)


if __name__ == "__main__":
    unittest.main()
