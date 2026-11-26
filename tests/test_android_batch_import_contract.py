"""Source-boundary checks only; device storage and UI need separate acceptance."""
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[1] / "mobile/android/app/src/main/java/ru/arvectum/proxylauncher"
ACTIVITY = (BASE / "MainActivity.kt").read_text()
STORE = (BASE / "storage/SecureProfileStore.kt").read_text()

class BatchImportContract(unittest.TestCase):
    def test_preview_and_explicit_save_boundary(self):
        editor = ACTIVITY.split("private fun showBatchImport()",1)[1].split("private fun showSubscriptionInput()",1)[0]
        preview = ACTIVITY.split("private fun showBatchPreview(",1)[1].split("private fun importSelectedTextFile(",1)[0]
        self.assertIn("ProxyStructuredImport.parseBatch", editor)
        self.assertIn("FLAG_SECURE", editor)
        self.assertIn("input.text.clear()", editor)
        self.assertNotIn("appendImportedProfiles", editor)
        self.assertIn("save.isEnabled = preview.items.isNotEmpty()", preview)
        self.assertLess(preview.index("save.setOnClickListener"), preview.index("store.appendImportedProfiles"))
        self.assertIn("if (!canBatchImport())", preview)
        self.assertNotIn("item.password", preview)
        self.assertNotIn("item.username", preview)
        self.assertNotIn("item.name", preview)
        self.assertNotIn("connectVpn()", preview)

    def test_file_import_uses_bounded_worker_and_no_persistent_permission(self):
        self.assertIn("Intent.ACTION_OPEN_DOCUMENT", ACTIVITY)
        self.assertIn('type = "*/*"', ACTIVITY)
        self.assertIn('"text/plain"', ACTIVITY)
        self.assertNotIn("takePersistableUriPermission", ACTIVITY)
        worker = ACTIVITY.split("private fun importSelectedTextFile(",1)[1].split("private fun chooseQrImage()",1)[0]
        self.assertIn("Thread {", worker)
        self.assertIn("use(ProxyBatchImport::readText)", worker)
        self.assertIn("generation != batchImportGeneration", worker)
        self.assertIn("batchFileReadInProgress = true", worker)
        self.assertNotIn("appendImportedProfiles", worker)

    def test_store_prepares_encrypted_values_and_preserves_existing_selection(self):
        store = STORE.split("fun appendImportedProfiles(",1)[1].split("fun listProfiles()",1)[0]
        self.assertIn("ProxyBatchImport.preview(items, listProfiles()).skipped == 0", store)
        self.assertLess(store.index("encrypt(chars, key)"), store.index("val editor = prefs.edit()"))
        self.assertIn("chars.fill(Char.MIN_VALUE)", store)
        self.assertIn("if (!editor.commit())", store)
        self.assertIn("rollback.commit()", store)
        for forbidden in ("KEY_ACTIVE_ID", "KEY_AUTO_SELECTION", "KEY_PRIMARY_ID", "saveProfile(", "deleteProfile("):
            self.assertNotIn(forbidden, store)

if __name__ == "__main__":
    unittest.main()
