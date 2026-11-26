"""Source checks; actual Android TLS, DNS and lifecycle acceptance is separate."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'mobile/android/app/src/main'
BASE = APP / 'java/ru/arvectum/proxylauncher'
MAIN = (BASE / 'MainActivity.kt').read_text()
FETCH = (BASE / 'importing/ProxySubscriptionFetch.kt').read_text()
POLICY = (BASE / 'model/ProxySubscriptionImport.kt').read_text()
GRADLE = (APP.parent.parent / 'build.gradle.kts').read_text()

class SubscriptionContract(unittest.TestCase):
    def test_explicit_masked_input_and_preview(self):
        block = MAIN.split('private fun showSubscriptionInput(',1)[1].split('private fun showImportFailure()',1)[0]
        self.assertIn('PasswordTransformationMethod',block)
        self.assertIn('FLAG_SECURE',block)
        self.assertIn('isSaveEnabled = false',block)
        self.assertIn('input.text.clear()',block)
        self.assertLess(block.index('setOnClickListener'),block.index('ProxySubscriptionFetch(raw)'))
        self.assertIn('if (subscriptionFetch !== fetch) return@post',block)
        self.assertIn('showBatchPreview(items)',block)
        self.assertIn('active?.cancel()',block)
        self.assertIn('cancelSubscription()',MAIN.split('override fun onPause()',1)[1].split('override fun onStop()',1)[0])
        for forbidden in ('appendImportedProfiles','connectVpn()','prefs.edit()','Log.'):
            self.assertNotIn(forbidden,block)

    def test_http_policy(self):
        for text in ('.proxy(Proxy.NO_PROXY)','.followRedirects(false)','.followSslRedirects(false)',
                     '.retryOnConnectionFailure(false)','.cookieJar(CookieJar.NO_COOKIES)',
                     '.authenticator(Authenticator.NONE)','.cache(null)', '.callTimeout(25, TimeUnit.SECONDS)',
                     'publicDns(hostname, source.host)','addresses.any { !ProxySubscriptionImport.publicAddress(it) }',
                     'response.code != 200','readBounded(body.byteStream(), canceled)',
                     '.header("Accept-Encoding", "identity")','call.cancel()'):
            self.assertIn(text,FETCH)
        for forbidden in ('hostnameVerifier(', 'sslSocketFactory(', 'HttpLoggingInterceptor','Log.'):
            self.assertNotIn(forbidden,FETCH)
        self.assertIn('ProxyBatchImport.MAX_BYTES',POLICY)
        self.assertIn('ProxyStructuredImport.parseBatch',POLICY)
        self.assertIn('uri.rawUserInfo != null',POLICY)

    def test_dependency_checks_and_localization(self):
        self.assertIn('verifySubscriptionArtifacts',GRADLE)
        for artifact in ('com.squareup.okhttp3:okhttp:4.12.0','com.squareup.okio:okio-jvm:3.6.0'):
            self.assertIn(artifact,GRADLE)
        for name in ('okhttp','okio'):
            self.assertTrue((APP/'assets/licenses'/name/'LICENSE').is_file())
        for d in (APP/'res').glob('values*'):
            if not (d/'strings.xml').is_file(): continue
            root=ET.parse(d/'subscription_import_strings.xml').getroot()
            self.assertEqual(len(root.findall('string')),4)

if __name__ == '__main__': unittest.main()
