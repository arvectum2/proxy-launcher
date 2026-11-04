"""Source-only contract for extra native half-close loopback tests in draft PR #314."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PATCH = (ROOT / "mobile/ios/Tools/tun2proxy-closewait-halfclose.patch").read_text()
FETCH = (ROOT / "mobile/ios/Tools/fetch_tun2proxy.py").read_text()


class NativeHalfCloseStressContract(unittest.TestCase):
    def test_real_upload_then_delayed_download_drains(self):
        self.assertIn("async fn real_client_fin_preserves_delayed_response_after_upload()", PATCH)
        self.assertIn("let expected_upload = uploaded.clone()", PATCH)
        self.assertIn("let expected_download = downloaded.clone()", PATCH)
        self.assertIn("browser.shutdown().await.unwrap()", PATCH)
        self.assertIn("tokio::time::sleep(Duration::from_millis(25))", PATCH)
        self.assertIn("assert_eq!(remote.await.unwrap(), expected_upload)", PATCH)
        self.assertIn("assert_eq!(browser_task.await.unwrap(), expected_download)", PATCH)

    def test_real_repeated_fin_leak_and_payload_loss_guard(self):
        self.assertIn("async fn repeated_real_upstream_fins_reap_open_browser_sockets()", PATCH)
        self.assertIn("for iteration in 0..20u8", PATCH)
        self.assertIn('TcpListener::bind("127.0.0.1:0")', PATCH)
        self.assertIn('expect("upstream FD retained after FIN")', PATCH)
        self.assertIn('assert_eq!(bytes, vec![iteration; 4096]', PATCH)
        self.assertIn('assert_eq!(remote.await.unwrap(), 0, "upstream must see EOF")', PATCH)

    def test_tests_only_add_to_existing_pinned_relay_patch(self):
        self.assertIn("+#[cfg(test)]", PATCH)
        self.assertIn("+mod apl_halfclose_regression_tests", PATCH)
        self.assertIn("std::time::Duration::from_secs(2)", PATCH)
        self.assertIn("std::time::Duration::from_secs(30)", PATCH)
        self.assertIn('CLOSE_WAIT_PATCH = TOOLS / "tun2proxy-closewait-halfclose.patch"', FETCH)
        self.assertIn('run("git", "apply", "--check", str(CLOSE_WAIT_PATCH), cwd=source)', FETCH)
        self.assertNotIn("github.com/", PATCH)
        self.assertNotIn("example.com", PATCH)


if __name__ == "__main__":
    unittest.main()
