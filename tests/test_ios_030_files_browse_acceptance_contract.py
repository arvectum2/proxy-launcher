"""Files acceptance runs only with synthetic simulator data, not owner's iPhone."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
TEST = ROOT / "mobile/ios/Tests/UITests/EncryptedFilesRoundtripUITests.swift"
CODEC = ROOT / "mobile/ios/SharedCore/ProfileBackup.swift"
APP = ROOT / "mobile/ios/App/ProfileBackupView.swift"


class FilesBrowseAcceptanceContracts(unittest.TestCase):
    def test_physical_devices_unconditionally_skip_explicit_files_qa(self):
        src = TEST.read_text()
        self.assertIn("#if APL_RUN_EXPLICIT_FILES_QA", src)
        self.assertIn("#if !targetEnvironment(simulator)", src)
        self.assertIn("Never use the owner's physical phone", src)
        self.assertIn("-aplBackupFilesQA", src)
        self.assertIn("aplBackupFilesQA", src)

    def test_real_synthetic_files_browse_replaces_recents_only_skip(self):
        src = TEST.read_text()
        self.assertIn("CGVector(dx: 0.73, dy: 0.95)", src)
        self.assertIn("CGVector(dx: 0.30, dy: 0.40)", src)
        self.assertIn("CGVector(dx: 0.17, dy: 0.33)", src)
        self.assertNotIn("throw XCTSkip(\"System Files provider did not expose", src)
        self.assertIn("testEncryptedFileCanBeSavedAndReimported", src)

    def test_decryption_and_idempotence_are_hard_assertions(self):
        src = TEST.read_text()
        self.assertIn('backup.import.password', src)
        self.assertIn('backup.import.restore', src)
        self.assertIn('Добавлено профилей: 0', src)
        self.assertIn('XCTAssertTrue(restoreSecret.waitForExistence(timeout: 10)', src)
        self.assertIn('app.buttons["backup.import.restore"].tap()', src)
        self.assertIn("testInspectDisposableFilesBrowseNavigation", src)

    def test_production_import_keeps_scoped_bounded_ciphertext_handling(self):
        codec = CODEC.read_text()
        view = APP.read_text()
        self.assertIn("static func readEncryptedFile(at url: URL) throws -> Data", codec)
        self.assertIn("startAccessingSecurityScopedResource()", view)
        self.assertIn("stopAccessingSecurityScopedResource()", view)
        self.assertIn("encryptedData = try ProfileBackupCodec.readEncryptedFile(at: file)", view)
        self.assertIn("ProfileBackupCodec.exportFilename()", view)


if __name__ == "__main__":
    unittest.main()
