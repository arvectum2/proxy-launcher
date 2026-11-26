"""Saved subscription storage and explicit refresh boundaries; not device acceptance."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'mobile/android/app/src/main'
BASE = APP / 'java/ru/arvectum/proxylauncher'
MAIN = (BASE / 'MainActivity.kt').read_text()
STORE = (BASE / 'storage/SecureSubscriptionStore.kt').read_text()
CATALOG = (BASE / 'model/SavedSubscriptionCatalog.kt').read_text()
REVIEW = (BASE / 'model/SavedSubscriptionReview.kt').read_text()

class SavedSubscriptionContract(unittest.TestCase):
    def test_separate_keystore_and_ciphertext_commit(self):
        for fragment in ('AndroidKeyStore','subscription_sources.v1','setKeySize(256)',
                         'setRandomizedEncryptionRequired(true)','key(allowCreate = false)',
                         'Context.MODE_PRIVATE','SavedSubscriptionCatalog.encode(updated)',
                         'rollback.commit()'):
            self.assertIn(fragment, STORE)
        self.assertIn('AES/GCM/NoPadding', CATALOG)
        self.assertIn('cipher.updateAAD(aad(', CATALOG)
        self.assertIn('plain.fill(0)', CATALOG)
        self.assertIn('MAX_SOURCES = 12', CATALOG)
        self.assertIn('stream.writeUTF(entry.encrypted)', CATALOG)
        self.assertNotIn('putString(CATALOG,raw)', STORE)
        self.assertNotIn('SecureProfileStore',STORE)
        root=ET.parse(APP/'AndroidManifest.xml').getroot()
        ns='{http://schemas.android.com/apk/res/android}'
        self.assertEqual(root.find('application').get(ns+'allowBackup'),'false')
        for category in ('cloud-backup','device-transfer'):
            self.assertTrue(any(e.get('domain')=='sharedpref' and e.get('path')=='.' for e in ET.parse(APP/'res/xml/data_extraction_rules.xml').getroot().find(category)))

    def test_explicit_saved_source_actions(self):
        menu=MAIN.split('private fun showSavedSubscriptions()',1)[1].split('private fun showSubscriptionInput(',1)[0]
        save=MAIN.split('private fun showSubscriptionInput(',1)[1].split('private fun startSubscription(',1)[0]
        self.assertIn('source.host',menu)
        self.assertIn('ProxySubscriptionFetch(subscriptionStore.source(source))',menu)
        self.assertLess(menu.index('.setPositiveButton(R.string.apl_subscription_download)'),menu.index('subscriptionStore.source(source)'))
        self.assertIn('confirmRemoveSubscription(source)',menu)
        self.assertIn('subscriptionStore.remove(source)',menu)
        self.assertIn('if (saveOnly)',save)
        self.assertLess(save.index('subscriptionStore.add(raw)'),save.index('ProxySubscriptionFetch(raw)'))
        self.assertIn('return@setOnClickListener',save.split('subscriptionStore.add(raw)',1)[1].split('ProxySubscriptionFetch(raw)',1)[0])
        for forbidden in ('deleteProfile(', 'saveProfile(', 'Log.', 'ClipboardManager'):
            self.assertNotIn(forbidden, menu+save+STORE)

    def test_review_expiry_baseline_and_lifecycle(self):
        self.assertIn('if (consumed) return null',REVIEW)
        self.assertIn('consumed = true',REVIEW)
        self.assertIn('current != source || existing != baseline',REVIEW)
        self.assertIn('age !in 0 until TTL_MS',REVIEW)
        self.assertIn('previous != null && previous != item.password',REVIEW)
        preview=MAIN.split('private fun showBatchPreview(',1)[1].split('private fun importSelectedTextFile(',1)[0]
        self.assertIn('subscriptionReviewDialog = dialog',preview)
        self.assertIn('review.cancel()',preview)
        self.assertLess(preview.index('review.confirm(current, store.listProfiles(), cameraUiResumed)'),preview.index('store.appendImportedProfiles(approved)'))
        cancel=MAIN.split('private fun cancelSubscription()',1)[1].split('private fun showImportFailure()',1)[0]
        self.assertIn('subscriptionReviewDialog?.dismiss()',cancel)
        self.assertIn('cancelSubscription()',MAIN.split('override fun onPause()',1)[1].split('override fun onStop()',1)[0])

    def test_resources(self):
        for d in (APP/'res').glob('values*'):
            if (d/'strings.xml').is_file():
                self.assertEqual(7,len(ET.parse(d/'saved_subscription_strings.xml').getroot().findall('string')))

if __name__=='__main__': unittest.main()
