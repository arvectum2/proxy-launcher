"""Managed storage source gate; no live UI activation or cross-process acceptance claimed."""
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[1] / 'mobile/android/app/src/main/java/ru/arvectum/proxylauncher'
STORE = (BASE/'storage/SecureProfileStore.kt').read_text()
TX = (BASE/'storage/ManagedPreferenceTransaction.kt').read_text()
MAIN = (BASE/'MainActivity.kt').read_text()

class ManagedStorageContract(unittest.TestCase):
    def test_atomic_affected_keys_and_strict_raw_snapshot(self):
        for text in ('const val IDS = "profile_ids"','const val JOURNAL = "managed_rollback_v1"',
                     'snapshot(raw,before.selection.selected) == before','before.selection == after.selection',
                     'it in before.protectedIds || (!firstImportRollback && it == effectivePrimary(before))',
                     'effectivePrimary(before) == effectivePrimary(after)',
                     'prior[it]?.owner == sourceId','next[it]?.owner == sourceId',
                     'fields.none { field(id,it) in raw }','IDS to next.keys.toSet(), JOURNAL to journal',
                     'patch[secret(id)] = row?.encryptedCredential'):
            self.assertIn(text,TX)
        self.assertIn('return editor.commit()',STORE)
        self.assertNotIn('editor.apply()',STORE.split('private val managedBackend',1)[1].split('private val managedTransaction',1)[0])

    def test_fault_outcome_latch_and_readback(self):
        for text in ('backend.read() == expected','committed && observed == target && gate()',
                     'observed.filterKeys { it !in patch } != expected.filterKeys { it !in patch }',
                     'patch.keys.associateWith { expected[it] }','backend.commit(restore)',
                     'if (recoveryRequired) return Outcome.RECOVERY_REQUIRED'):
            self.assertIn(text,TX)
        self.assertIn('managedRecoveryRequired = true',STORE)

    def test_encrypted_journal_and_device_activation_gate(self):
        for text in ('managed_rollback.v1','managedJournalKey(false)','existingCredentialKey()',
                     'ManagedRollbackJournal.open(previousJournal as String,journalKey)',
                     'ManagedRollbackJournal.from(txn).seal(journalKey)',
                     'journal.restore(source,before,gate())','ManagedPreferenceSchema.rollbackPatch(raw,before,source,journalKey,gate())',
                     'managedTransaction.execute(raw,patch,gate)','manager.runningAppProcesses',
                     'android.os.Looper.myLooper() != android.os.Looper.getMainLooper()'):
            self.assertIn(text,STORE)
        for text in ('prepareManagedRefresh(','applyManagedRefresh(','rollbackManagedRefresh('):
            self.assertNotIn(text,MAIN)
        self.assertNotIn('startVpnService',TX)

if __name__ == '__main__': unittest.main()
