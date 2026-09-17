import unittest
from types import SimpleNamespace

from linux_networkmanager_preflight import (
    PreflightStatus,
    detect_networkmanager_preflight,
)
from linux_runtime import LinuxRuntimeEnvironment


class FakeRunner:
    def __init__(self, responses):
        self.responses = responses
        self.calls = []

    def __call__(self, arguments, timeout=10):
        key = tuple(arguments[1:])
        self.calls.append(key)
        return self.responses.get(key, SimpleNamespace(returncode=1, stdout="", stderr="missing"))


def result(code=0, stdout="", stderr=""):
    return SimpleNamespace(returncode=code, stdout=stdout, stderr=stderr)


def runtime(nmcli_path="/usr/bin/nmcli", is_astra=True):
    return LinuxRuntimeEnvironment(
        distro_id="astra" if is_astra else "debian",
        id_like=("debian",),
        name="Astra Linux" if is_astra else "Debian GNU/Linux",
        pretty_name="Astra Linux",
        version_id="1.8_x86-64",
        version_codename="1.8_x86-64",
        variant="",
        variant_id="",
        astra_version="",
        kernel_release="6.1.0",
        architecture="x86_64",
        desktop_environment="FLY",
        session_type="x11",
        nmcli_path=nmcli_path,
        is_astra=is_astra,
        is_redos=False,
        is_debian_family=True,
        network_manager_client_available=bool(nmcli_path),
    )


def ready_responses(permission="yes"):
    uuid = "11111111-2222-3333-4444-555555555555"
    responses = {
        ("--version",): result(stdout="nmcli tool, version 1.42.4\n"),
        ("--terse", "--fields", "STATE,CONNECTIVITY", "general", "status"):
            result(stdout="connected:full\n"),
        ("--terse", "--escape", "no", "--fields", "UUID,TYPE,DEVICE", "connection", "show", "--active"):
            result(stdout=f"{uuid}:802-3-ethernet:eth0\n"),
        ("--terse", "--fields", "PERMISSION,VALUE", "general", "permissions"):
            result(stdout=(
                f"org.freedesktop.NetworkManager.settings.modify.system:{permission}\n"
                "org.freedesktop.NetworkManager.settings.modify.own:no\n"
            )),
    }
    for prop, value in (
        ("proxy.method", "none"),
        ("proxy.browser-only", "no"),
        ("proxy.pac-url", ""),
        ("proxy.pac-script", ""),
    ):
        responses[("--escape", "no", "--get-values", prop, "connection", "show", "uuid", uuid)] = result(stdout=value)
    return responses


class NetworkManagerPreflightTests(unittest.TestCase):
    def test_ready_when_daemon_profile_proxy_surface_and_permission_exist(self):
        runner = FakeRunner(ready_responses("yes"))
        probe = detect_networkmanager_preflight(runtime=runtime(), runner=runner)
        self.assertEqual(probe.status, PreflightStatus.READY)
        self.assertTrue(probe.operational)
        self.assertEqual(probe.nmcli_version, "1.42.4")
        self.assertEqual(probe.networkmanager_state, "connected")
        self.assertEqual(probe.connectivity, "full")
        self.assertTrue(probe.proxy_setting_supported)
        self.assertEqual(len(probe.supported_active_connection_uuids), 1)
        self.assertEqual(probe.reasons, ())

    def test_auth_required_is_distinct_from_unavailable(self):
        probe = detect_networkmanager_preflight(
            runtime=runtime(), runner=FakeRunner(ready_responses("auth"))
        )
        self.assertEqual(probe.status, PreflightStatus.AUTH_REQUIRED)
        self.assertFalse(probe.operational)
        self.assertTrue(probe.can_attempt_with_authorization)
        self.assertIn("PolicyKit", " ".join(probe.reasons))

    def test_missing_nmcli_fails_closed_without_commands(self):
        runner = FakeRunner({})
        probe = detect_networkmanager_preflight(runtime=runtime(nmcli_path=""), runner=runner)
        self.assertEqual(probe.status, PreflightStatus.UNAVAILABLE)
        self.assertEqual(runner.calls, [])
        self.assertIn("nmcli", probe.reasons[0])

    def test_unreachable_daemon_fails_closed(self):
        responses = ready_responses("yes")
        responses[("--terse", "--fields", "STATE,CONNECTIVITY", "general", "status")] = result(
            code=10, stderr="NetworkManager is not running"
        )
        probe = detect_networkmanager_preflight(runtime=runtime(), runner=FakeRunner(responses))
        self.assertEqual(probe.status, PreflightStatus.UNAVAILABLE)
        self.assertIn("daemon", " ".join(probe.reasons))

    def test_vpn_and_loopback_are_not_backend_targets(self):
        responses = ready_responses("yes")
        responses[("--terse", "--escape", "no", "--fields", "UUID,TYPE,DEVICE", "connection", "show", "--active")] = result(
            stdout="a:vpn:tun0\nb:loopback:lo\n"
        )
        probe = detect_networkmanager_preflight(runtime=runtime(), runner=FakeRunner(responses))
        self.assertEqual(probe.status, PreflightStatus.UNAVAILABLE)
        self.assertEqual(probe.active_connection_uuids, ("a", "b"))
        self.assertEqual(probe.supported_active_connection_uuids, ())

    def test_missing_proxy_properties_fails_closed(self):
        responses = ready_responses("yes")
        uuid = "11111111-2222-3333-4444-555555555555"
        responses[("--escape", "no", "--get-values", "proxy.pac-url", "connection", "show", "uuid", uuid)] = result(
            code=2, stderr="unknown property"
        )
        probe = detect_networkmanager_preflight(runtime=runtime(), runner=FakeRunner(responses))
        self.assertEqual(probe.status, PreflightStatus.UNAVAILABLE)
        self.assertFalse(probe.proxy_setting_supported)

    def test_permission_no_fails_closed(self):
        probe = detect_networkmanager_preflight(
            runtime=runtime(), runner=FakeRunner(ready_responses("no"))
        )
        self.assertEqual(probe.status, PreflightStatus.UNAVAILABLE)
        self.assertIn("not permitted", " ".join(probe.reasons))


if __name__ == "__main__":
    unittest.main()
