import unittest
from types import SimpleNamespace

from linux_desktop_proxy import (
    DesktopProxyError,
    DesktopProxyState,
    GSettingsProxyClient,
    detect_desktop_proxy_client,
)


class _GSettingsRunner:
    def __init__(self):
        self.values = {
            "mode": "none",
            "autoconfig-url": "",
        }
        self.writable = {
            "mode": True,
            "autoconfig-url": True,
        }
        self.calls = []

    def __call__(self, argv, **kwargs):
        self.calls.append((tuple(argv), dict(kwargs)))
        operation = argv[1]
        key = argv[3] if len(argv) > 3 else ""
        if operation == "get":
            return SimpleNamespace(
                returncode=0,
                stdout=repr(self.values[key]) + "\n",
                stderr="",
            )
        if operation == "writable":
            return SimpleNamespace(
                returncode=0,
                stdout=("true\n" if self.writable[key] else "false\n"),
                stderr="",
            )
        if operation == "set":
            self.values[key] = argv[4].strip("'\"")
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        raise AssertionError(argv)


class GSettingsProxyClientTests(unittest.TestCase):
    def test_reads_and_sets_only_pac_keys_with_verification(self):
        runner = _GSettingsRunner()
        client = GSettingsProxyClient(
            binary="/usr/bin/gsettings",
            runner=runner,
            environ={"DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1001/bus"},
        )
        self.assertEqual(client.get_state(), DesktopProxyState("none", ""))

        desired = DesktopProxyState(
            "auto", "http://127.0.0.1:8082/proxy.pac"
        )
        client.set_state(desired)
        self.assertEqual(client.get_state(), desired)
        set_keys = [
            call[0][3]
            for call in runner.calls
            if len(call[0]) > 3 and call[0][1] == "set"
        ]
        self.assertEqual(set_keys, ["autoconfig-url", "mode"])

    def test_nonwritable_key_fails_before_any_set(self):
        runner = _GSettingsRunner()
        runner.writable["mode"] = False
        client = GSettingsProxyClient(runner=runner, environ={})
        with self.assertRaises(DesktopProxyError):
            client.set_state(DesktopProxyState("auto", "http://127.0.0.1/pac"))
        self.assertFalse(any(call[0][1] == "set" for call in runner.calls))

    def test_detects_fly_session_with_gsettings_and_dbus(self):
        runner = _GSettingsRunner()
        client = detect_desktop_proxy_client(
            environ={
                "XDG_CURRENT_DESKTOP": "Fly",
                "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1001/bus",
            },
            which=lambda name: "/usr/bin/gsettings" if name == "gsettings" else None,
            runner=runner,
        )
        self.assertIsInstance(client, GSettingsProxyClient)

    def test_unsupported_desktop_does_not_mutate_unrelated_store(self):
        client = detect_desktop_proxy_client(
            environ={
                "XDG_CURRENT_DESKTOP": "KDE",
                "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1001/bus",
            },
            which=lambda name: "/usr/bin/gsettings",
        )
        self.assertIsNone(client)

    def test_explicit_session_bus_does_not_require_posix_uid_lookup(self):
        client = detect_desktop_proxy_client(
            environ={
                "XDG_CURRENT_DESKTOP": "Fly",
                "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1001/bus",
            },
            which=lambda name: "/usr/bin/gsettings" if name == "gsettings" else None,
        )
        self.assertIsInstance(client, GSettingsProxyClient)

    def test_graphical_desktop_without_session_bus_is_not_claimed(self):
        client = detect_desktop_proxy_client(
            environ={"XDG_CURRENT_DESKTOP": "Fly", "XDG_RUNTIME_DIR": "/missing"},
            which=lambda name: "/usr/bin/gsettings",
        )
        self.assertIsNone(client)


if __name__ == "__main__":
    unittest.main()
