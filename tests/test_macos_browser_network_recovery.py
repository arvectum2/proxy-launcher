import unittest
from unittest import mock

import macos_browser_network_recovery as recovery
import proxy_core as core


class MacOSBrowserNetworkRecoveryTests(unittest.TestCase):
    def test_non_macos_has_no_candidates(self):
        with mock.patch.object(recovery.sys, "platform", "linux"), \
             mock.patch.object(recovery, "_process_rows") as rows:
            self.assertEqual(recovery._browser_network_candidates(), [])
        rows.assert_not_called()

    def test_chrome_network_service_requires_exact_parent_and_system_proxy_mode(self):
        rows = [
            {
                "uid": 501,
                "pid": 100,
                "ppid": 1,
                "command": "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            },
            {
                "uid": 501,
                "pid": 101,
                "ppid": 100,
                "command": (
                    "/Applications/Google Chrome.app/.../Google Chrome Helper "
                    "--type=utility --utility-sub-type=network.mojom.NetworkService"
                ),
            },
            {
                "uid": 501,
                "pid": 200,
                "ppid": 1,
                "command": (
                    "/Users/master/Downloads/Chromium-Gost.app/Contents/MacOS/"
                    "Chromium-Gost.bak --no-proxy-server"
                ),
            },
            {
                "uid": 501,
                "pid": 201,
                "ppid": 200,
                "command": (
                    "/Users/master/Downloads/Chromium-Gost.app/.../"
                    "Chromium-Gost Helper --type=utility "
                    "--utility-sub-type=network.mojom.NetworkService"
                ),
            },
        ]
        with mock.patch.object(recovery.sys, "platform", "darwin"), \
             mock.patch.object(recovery.os, "getuid", return_value=501), \
             mock.patch.object(recovery, "_process_rows", return_value=rows), \
             mock.patch.object(recovery, "_pid_uses_safari_container", return_value=False):
            self.assertEqual(
                recovery._browser_network_candidates(),
                [("google_chrome", 101)],
            )

    def test_safari_network_service_requires_safari_container_proof(self):
        rows = [
            {
                "uid": 501,
                "pid": 300,
                "ppid": 1,
                "command": (
                    "/System/Library/Frameworks/WebKit.framework/Versions/A/"
                    "XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS/"
                    "com.apple.WebKit.Networking"
                ),
            },
            {
                "uid": 501,
                "pid": 301,
                "ppid": 1,
                "command": (
                    "/System/Library/Frameworks/WebKit.framework/Versions/A/"
                    "XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS/"
                    "com.apple.WebKit.Networking"
                ),
            },
        ]
        with mock.patch.object(recovery.sys, "platform", "darwin"), \
             mock.patch.object(recovery.os, "getuid", return_value=501), \
             mock.patch.object(recovery, "_process_rows", return_value=rows), \
             mock.patch.object(
                 recovery,
                 "_pid_uses_safari_container",
                 side_effect=lambda pid: pid == 300,
             ):
            self.assertEqual(
                recovery._browser_network_candidates(),
                [("safari", 300)],
            )

    def test_recovery_signals_only_proven_candidates(self):
        candidates = [("safari", 300), ("google_chrome", 101)]
        with mock.patch.object(
                 recovery, "_browser_network_candidates", return_value=candidates
             ), \
             mock.patch.object(recovery.os, "kill") as kill, \
             mock.patch.object(core, "structured_log") as log:
            self.assertEqual(
                core.recover_browser_network_services(),
                candidates,
            )

        self.assertEqual(
            [call.args for call in kill.call_args_list],
            [(300, recovery.signal.SIGKILL), (101, recovery.signal.SIGKILL)],
        )
        self.assertEqual(log.call_args.kwargs["phase"], "completed")
        self.assertEqual(log.call_args.kwargs["recycled_count"], 2)

    def test_recovery_is_fail_closed_if_signal_fails(self):
        with mock.patch.object(
                 recovery, "_browser_network_candidates",
                 return_value=[("safari", 300)],
             ), \
             mock.patch.object(recovery.os, "kill", side_effect=PermissionError), \
             mock.patch.object(core, "structured_log") as log:
            self.assertEqual(core.recover_browser_network_services(), [])

        phases = [call.kwargs["phase"] for call in log.call_args_list]
        self.assertEqual(phases, ["scan", "signal_failed", "completed"])


if __name__ == "__main__":
    unittest.main()
