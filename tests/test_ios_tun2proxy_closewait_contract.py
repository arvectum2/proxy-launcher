"""iOS rust/tun2proxy native CLOSE_WAIT source pinning and ordering contracts."""
from pathlib import Path
import unittest

IOS = Path(__file__).resolve().parents[1] / "mobile" / "ios"
FETCH = (IOS / "Tools" / "fetch_tun2proxy.py").read_text(encoding="utf-8")
PATCH = (IOS / "Tools" / "tun2proxy-closewait-halfclose.patch").read_text(encoding="utf-8")


class IOSCloseWaitNativeContractTests(unittest.TestCase):
    def test_pinned_patch_is_applied_after_smart3_dual_stack_patch(self):
        self.assertIn('SOURCE_COMMIT = "e271de19683937f23d3f8f0eb4df0a61fc4a6e50"', FETCH)
        self.assertIn('CLOSE_WAIT_PATCH = TOOLS / "tun2proxy-closewait-halfclose.patch"', FETCH)
        self.assertIn('run("git", "apply", "--check", str(CLOSE_WAIT_PATCH), cwd=source)', FETCH)
        self.assertIn('run("git", "apply", str(CLOSE_WAIT_PATCH), cwd=source)', FETCH)
        self.assertLess(
            FETCH.index('run("git", "apply", str(DIRECT_FAMILY_PATCH), cwd=source)'),
            FETCH.index('run("git", "apply", str(CLOSE_WAIT_PATCH), cwd=source)'),
        )

    def test_builder_uses_active_xcode_outside_applications(self):
        # Hosted macOS may use /Applications; Mac mini selects an external
        # Xcode path. Both must be supported without manual env injection.
        self.assertIn('["xcode-select", "-p"]', FETCH)
        self.assertIn('candidates.append(Path(selected.stdout.strip()))', FETCH)
        self.assertLess(
            FETCH.index('candidates.append(Path(selected.stdout.strip()))'),
            FETCH.index('candidates.append(Path("/Applications/Xcode.app/Contents/Developer"))'),
        )

    def test_half_closed_upstream_has_bounded_shutdown_both_directions(self):
        self.assertIn('async fn bounded_half_close<C, S>(', PATCH)
        self.assertIn('let res = bounded_half_close(', PATCH)
        self.assertIn('std::time::Duration::from_secs(2)', PATCH)
        self.assertIn('std::time::Duration::from_secs(30)', PATCH)
        self.assertNotIn('+    let res = tokio::join!(', PATCH)
        for test in (
            "upstream_fin_reaps_pending_client_forwarder",
            "client_fin_reaps_pending_upstream_forwarder",
            "real_tcp_fin_closes_proxy_fd_while_browser_remains_open",
            "both_sides_finish_immediately",
        ):
            self.assertIn(f"async fn {test}(", PATCH)

    def test_existing_routing_and_credentials_are_untouched(self):
        # The patch is deliberately limited to the relay's half-close
        # lifecycle and its Rust regressions, not routes or profile secrets.
        changed = [
            line[1:] for line in PATCH.splitlines()
            if line.startswith("+") and not line.startswith("+++")
        ]
        self.assertFalse(any("password" in line.lower() for line in changed))
        self.assertFalse(any("excludedroutes" in line.lower() for line in changed))
        self.assertIn("PATCHED_BLOCK", FETCH)
        self.assertIn('RUST_TOOLCHAIN = "1.98.1"', FETCH)


if __name__ == "__main__":
    unittest.main()
