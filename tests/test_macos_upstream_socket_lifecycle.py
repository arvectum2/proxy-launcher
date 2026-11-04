"""Contract checks for Mac Catalyst's native TCP half-close lifecycle fix."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROVIDER = (ROOT / "mobile/ios/PacketTunnel/PacketTunnelProvider.swift").read_text()
FETCH = (ROOT / "mobile/macos-appstore/Tools/fetch_tun2proxy.py").read_text()
PATCH = (ROOT / "mobile/macos-appstore/Tools/tun2proxy-closewait-halfclose.patch").read_text()

class MacOSUpstreamSocketLifecycleContract(unittest.TestCase):
    def test_no_infinite_join_of_half_closed_sockets(self):
        self.assertIn("+async fn bounded_half_close<C, S>", PATCH)
        self.assertIn("+    tokio::select! {", PATCH)
        self.assertIn("std::time::Duration::from_secs(2)", PATCH)
        self.assertIn("std::time::Duration::from_secs(30)", PATCH)
        self.assertIn("apl_halfclose_regression_tests", PATCH)

    def test_darwin_closewait_guard_covers_stalled_client_writes(self):
        for marker in (
            "+fn upstream_socket_in_close_wait(",
            "libc::TCP_CONNECTION_INFO",
            "info.tcpi_state == 5",
            "+async fn wait_for_upstream_close_wait(",
            "wait_for_upstream_close_wait(upstream_fd)",
            "tcp_close_wait_detected_while_virtual_output_is_blocked",
            "session_tasks.abort_all();",
            "session_tasks.join_next().await",
            "native_session_handoff_drops_stale_upstream_fd",
        ):
            self.assertIn(marker, PATCH)

    def test_current_smart3_ffi_is_preserved_in_native_build(self):
        for name in ("FLOW_INTENT_PATCH", "SCOPED_DIRECT_PATCH",
                     "SAME_FLOW_RETRY_PATCH", "DIRECT_FAMILY_PATCH", "CLOSE_WAIT_PATCH"):
            self.assertIn(name, FETCH)
        self.assertIn("install_flow_event_header(module_headers)", FETCH)
        self.assertIn("tun2proxy_set_flow_event_callback", FETCH)
        self.assertIn("tun2proxy_set_direct_exact_host", FETCH)

    def test_session_limit_only_applies_to_mac_catalyst(self):
        anchor='args += " --max-sessions 96"'
        self.assertIn(anchor, PROVIDER)
        self.assertIn('#if targetEnvironment(macCatalyst)', PROVIDER.split(anchor)[0][-460:])
        self.assertIn('softSocketLimit: 108', PROVIDER)
        self.assertIn('resetConnectionPressurePolicy()', PROVIDER)

if __name__ == "__main__":
    unittest.main()
