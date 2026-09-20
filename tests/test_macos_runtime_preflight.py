import unittest

from macos_networksetup_preflight import (
    MacOSPreflightStatus,
    detect_macos_network_preflight,
)
from macos_runtime import MacOSRuntimeDetectionError, detect_macos_runtime


class Result:
    def __init__(self, code=0, out="", err=""):
        self.returncode = code; self.stdout = out; self.stderr = err


class MacOSRuntimePreflightTests(unittest.TestCase):
    def test_runtime_rejects_non_darwin(self):
        with self.assertRaises(MacOSRuntimeDetectionError):
            detect_macos_runtime(platform_name="linux")

    def test_runtime_is_read_only_and_explicit(self):
        env = detect_macos_runtime(
            platform_name="darwin",
            environ={"USER": "tester"},
            which=lambda name: {"networksetup":"/usr/sbin/networksetup","launchctl":"/bin/launchctl","hdiutil":"/usr/bin/hdiutil"}.get(name),
            mac_ver=lambda: ("15.6", ("", "", ""), ""),
            machine=lambda: "arm64",
        )
        self.assertEqual(env.product_version, "15.6")
        self.assertEqual(env.architecture, "arm64")
        self.assertTrue(env.networksetup_available)

    def test_preflight_ready_when_all_enabled_services_are_readable(self):
        runtime = detect_macos_runtime(platform_name="darwin", which=lambda n: "/usr/sbin/networksetup" if n == "networksetup" else "", mac_ver=lambda:("15.6",(),""), machine=lambda:"arm64")
        def runner(args, timeout=10):
            if args[-1] == "-listallnetworkservices":
                return Result(out="An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n*USB 10/100/1000 LAN\n")
            if "-getautoproxyurl" in args:
                return Result(out="URL: http://127.0.0.1/proxy.pac\nEnabled: No\n")
            if "-getproxybypassdomains" in args:
                return Result(out="There aren't any bypass domains set on Wi-Fi.\n")
            return Result(1)
        result = detect_macos_network_preflight(runtime=runtime, runner=runner)
        self.assertEqual(result.status, MacOSPreflightStatus.READY)
        self.assertEqual(result.enabled_services, ("Wi-Fi",))

    def test_preflight_fails_closed_without_services(self):
        runtime = detect_macos_runtime(platform_name="darwin", which=lambda n: "/usr/sbin/networksetup" if n == "networksetup" else "", mac_ver=lambda:("15.6",(),""), machine=lambda:"arm64")
        result = detect_macos_network_preflight(runtime=runtime, runner=lambda args, timeout=10: Result(out="An asterisk (*) denotes that a network service is disabled.\n*Wi-Fi\n"))
        self.assertEqual(result.status, MacOSPreflightStatus.UNAVAILABLE)

if __name__ == "__main__":
    unittest.main()