"""Backup privacy: typed 64-locale failures, no raw file/crypto diagnostics."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"
VIEW = (IOS / "App/ProfileBackupView.swift").read_text()
UX = (IOS / "App/ProfileBackupUX.swift").read_text()
CORE = (IOS / "SharedCore/ProfileBackup.swift").read_text()
LOCALES = sorted((IOS / "Resources").glob("*.lproj/ProfileManagement.strings"))


class ProfileBackupErrorDisplayContract(unittest.TestCase):
    def test_all_seven_core_errors_are_translated_in_all_64_languages(self):
        block = CORE.split("enum ProfileBackupError: LocalizedError {", 1)[1]
        block = block.split("private struct ProfileBackupEnvelope", 1)[0]
        keys = re.findall(r'case \.\w+: return "([^"]+)"', block)
        self.assertEqual(len(keys), 7)
        self.assertEqual(len(LOCALES), 64)
        for file in LOCALES:
            text = file.read_text()
            for key in keys:
                with self.subTest(locale=file.parent.name, key=key):
                    self.assertIn('"' + key + '" = ', text)

    def test_typed_error_uses_the_correct_table(self):
        self.assertIn("error as? ProfileBackupError", UX)
        self.assertIn('AppL10n.tr(safeKey, table: "ProfileManagement")', UX)
        self.assertNotIn('AppL10n.tr(error.localizedDescription)', VIEW)

    def test_unknown_platform_errors_never_reveal_raw_details(self):
        self.assertNotIn("localizedDescription", VIEW)
        self.assertNotIn("localizedDescription", UX)
        self.assertNotIn("String(describing:", VIEW)
        self.assertNotIn("String(describing:", UX)
        self.assertNotIn("print(", UX)
        self.assertNotIn("Logger(", UX)
        self.assertIn('AppL10n.effectiveLanguage == "ru"', UX)
        for english in (
            "Could not save the backup file. Choose another location.",
            "Could not read the selected backup file.",
            "Could not create the encrypted backup.",
            "Could not restore profiles from the backup.",
        ):
            self.assertIn(english, UX)

    def test_every_file_and_crypto_failure_is_contextualized(self):
        for op in ("exportFile", "importFile", "createBackup", "restoreBackup"):
            with self.subTest(operation=op):
                self.assertIn("case ." + op + ":", UX)
                self.assertIn(
                    "ProfileBackupUX.message(error, operation: ." + op + ")", VIEW
                )
        self.assertEqual(VIEW.count("ProfileBackupUX.message(error"), 4)

    def test_export_cancellation_is_still_silent(self):
        self.assertIn("NSUserCancelledError", VIEW)
        self.assertRegex(
            VIEW,
            r"if \(error as NSError\)\.code != NSUserCancelledError\s*\{\s*"
            r"errorMessage = ProfileBackupUX\.message"
        )

    def test_backup_codec_and_profile_storage_logic_untouched_by_ui(self):
        self.assertIn("ProfileBackupCodec.maxFileBytes", VIEW)
        self.assertIn("file.startAccessingSecurityScopedResource()", VIEW)
        self.assertIn("file.stopAccessingSecurityScopedResource()", VIEW)
        self.assertIn("EncryptedProfileBackupDocument(encryptedData: encrypted)", VIEW)
        self.assertIn("model.restoreEncryptedProfileBackup(", VIEW)
        code_only = "\n".join(line for line in UX.splitlines()
                              if not line.lstrip().startswith("//"))
        for forbidden in ("SecItem", "Keychain", "NetworkExtension",
                          "startVPNTunnel", "URLSession", "UIPasteboard"):
            self.assertNotIn(forbidden, code_only)


if __name__ == "__main__":
    unittest.main()
