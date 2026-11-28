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
    def test_exclusive_preparation_and_preview(self):
        tx=(BASE/'storage/ManagedCrashTransaction.kt').read_text()
        self.assertLess(tx.index('val acquisition = gate.acquire()'),tx.index('val patch = runCatching(prepare)'))
        self.assertLess(tx.index('!durable(expected)'),tx.index('val patch = runCatching(prepare)'))
        self.assertLess(tx.index('val patch = runCatching(prepare)'),tx.index('lease.beginMutation(evidence)'))
        review=(BASE/'storage/ManagedChangeReview.kt').read_text()
        self.assertIn('transaction.executePrepared(expected,permitted,makePatch)',review)
        self.assertIn('validateRefreshPreview(raw,baseline,projection)',review)
    def test_session_remains_dormant(self):
        session=(BASE/'storage/ManagedReviewSession.kt').read_text()
        self.assertIn('current === ticket',session)
        self.assertIn('cancel?.invoke()',session)
        self.assertNotIn('ManagedReviewSession(', (BASE/'MainActivity.kt').read_text())
    def test_no_unreviewed_rollback_or_ui_activation(self):
        store=(BASE/'storage/SecureProfileStore.kt').read_text()
        self.assertNotIn('fun rollbackManagedRefresh(',store)
        self.assertNotIn('fun applyManagedRefresh(',store)
        for name in ('MainActivity.kt','tunnel/ProxyVpnService.kt'):
            content=(BASE/name).read_text()
            for call in ('prepareManagedRefresh(','prepareManagedRollback(','confirmManagedChange(','managedFetchInput('):
                self.assertNotIn(call,content)
    def test_guarded_controller_and_fetch_do_not_fall_back(self):
        main=(BASE/'MainActivity.kt').read_text()
        controller=(BASE/'ui/ManagedSubscriptionController.kt').read_text()
        self.assertIn('const val ENABLED = false',controller)
        self.assertIn('if (!ManagedSubscriptionActivation.ENABLED) null else ManagedSubscriptionController(',main)
        self.assertIn('ProxySubscriptionFetch(it.url)',main)
        self.assertIn('if (managedRequest != null) { managedSubscriptions?.receive(managedRequest,items);return@post }',main)
        self.assertIn('store.prepareManagedRefresh(catalog,request.input,items,selected())',controller)
        self.assertIn('if(!dialogs.permits(ticket) || !allowed()) return',controller)
        self.assertIn('managedSubscriptions?.invalidate()',main)
        self.assertIn('if(error is ManagedRecoveryRequiredException) R.string.managed_recovery_required else fallback',main)
if __name__=='__main__': unittest.main()
