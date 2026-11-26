"""Pure core contract only; managed apply/rollback is intentionally not wired to storage/UI yet."""
from pathlib import Path
import unittest

BASE=Path(__file__).resolve().parents[1]/'mobile/android/app/src/main/java/ru/arvectum/proxylauncher'
PLAN=(BASE/'model/ManagedSubscriptionRefresh.kt').read_text()
JOURNAL=(BASE/'model/ManagedRollbackJournal.kt').read_text()
MAIN=(BASE/'MainActivity.kt').read_text()
STORE=(BASE/'storage/SecureProfileStore.kt').read_text()

class ManagedRefreshContract(unittest.TestCase):
    def test_planner_only_changes_explicitly_owned_rows(self):
        for fragment in ('it.owner == source.id','if (matching.isNotEmpty()) { skipped++; continue }',
                         'current.protectedIds','current != baseline','currentSource != source',
                         'elapsed() - started !in 0 until TTL_MS','consumed = true',
                         'previous.password != item.password','incoming.size !in 1..ProxyBatchImport.MAX_ENTRIES'):
            self.assertIn(fragment,PLAN)
        self.assertIn('changes.none { it.kind != Kind.REMOVE }',PLAN)
        self.assertIn('current != after',PLAN)

    def test_encrypted_journal_is_bounded_and_post_state_guarded(self):
        for fragment in ('AES/GCM/NoPadding','cipher.updateAAD(AAD)','MAX_BYTES = 2_097_152',
                         'MAX_CHANGED = 400','changed == transaction.changedIds',
                         'changed.associateWith { before[it] }','MessageDigest.isEqual(expectedAfter, fingerprint(current))',
                         'previous.keys.any { it in current.protectedIds }','currentSource != source',
                         'plain.fill(0)','out.wipe()'):
            self.assertIn(fragment,JOURNAL)
        self.assertIn('transaction.before.selection == transaction.after.selection',JOURNAL)
        self.assertIn('before[id]?.owner == transaction.source.id',JOURNAL)
        self.assertIn('after[id]?.owner == transaction.source.id',JOURNAL)

    def test_core_has_no_live_mutation_or_activation(self):
        for fragment in ('SharedPreferences','android.content','startActivity','connectVpn','ProxySubscriptionFetch','Log.'):
            self.assertNotIn(fragment,PLAN+JOURNAL)
        for fragment in ('ManagedSubscriptionRefresh','ManagedRollbackJournal'):
            self.assertNotIn(fragment,MAIN+STORE)

if __name__=='__main__': unittest.main()
