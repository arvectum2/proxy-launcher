from pathlib import Path
import unittest
BASE=Path(__file__).resolve().parents[1]/'mobile/android/app/src/main/java/ru/arvectum/proxylauncher'
class ChangeReviewContract(unittest.TestCase):
    def test_authenticated_fetch_revision_and_exact_review(self):
        catalog=(BASE/'storage/SecureSubscriptionStore.kt').read_text()
        self.assertIn('ManagedFetchInput(expected,revision,SavedSubscriptionCatalog.open',catalog)
        store=(BASE/'storage/SecureProfileStore.kt').read_text()
        self.assertIn('revision != fetched.revision',store)
        self.assertIn('catalog.withManagedCatalog',store)
        self.assertIn('verifiedManagedDiskState()',store)
        self.assertIn('review.confirm(managedTransaction,managedBackend::read',store)
        review=(BASE/'storage/ManagedChangeReview.kt').read_text()
        for token in ('currentRaw() == expected','currentRevision() == revision','currentSelection() == selected','elapsed()-started in 0 until TTL_MS','replacesRollback && !acceptRollbackReplacement','finally { cancelPlan() }'):
            self.assertIn(token,review)
    def test_no_unreviewed_rollback_or_ui_activation(self):
        store=(BASE/'storage/SecureProfileStore.kt').read_text()
        self.assertNotIn('fun rollbackManagedRefresh(',store)
        self.assertNotIn('fun applyManagedRefresh(',store)
        for name in ('MainActivity.kt','tunnel/ProxyVpnService.kt'):
            content=(BASE/name).read_text()
            for call in ('prepareManagedRefresh(','prepareManagedRollback(','confirmManagedChange(','managedFetchInput('):
                self.assertNotIn(call,content)
if __name__=='__main__': unittest.main()
