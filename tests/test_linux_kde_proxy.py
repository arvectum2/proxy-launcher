import unittest
from types import SimpleNamespace

from linux_desktop_proxy import DesktopProxyError, DesktopProxyState
from linux_kde_proxy import KdeProxyClient


class _KdeRunner:
    def __init__(self):
        self.values = {
            "ProxyType": "1",
            "Proxy Config Script": "",
            "httpProxy": "http://existing.proxy 8000",
            "NoProxyFor": "localhost,127.0.0.1",
        }
        self.calls = []
        self.fail_write_key = None

    def __call__(self, argv, **kwargs):
        self.calls.append((tuple(argv), dict(kwargs)))
        binary = argv[0]
        if binary.endswith("kreadconfig5"):
            key = argv[argv.index("--key") + 1]
            return SimpleNamespace(returncode=0, stdout=self.values.get(key, "") + "\n", stderr="")
        if binary.endswith("kwriteconfig5"):
            key = argv[argv.index("--key") + 1]
            value = argv[-1]
            if key == self.fail_write_key:
                return SimpleNamespace(returncode=1, stdout="", stderr="injected")
            self.values[key] = value
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if binary.endswith("dbus-send"):
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        raise AssertionError(argv)


class KdeProxyClientTests(unittest.TestCase):
    def make_client(self, runner):
        return KdeProxyClient(
            read_binary="/usr/bin/kreadconfig5",
            write_binary="/usr/bin/kwriteconfig5",
            signal_binary="/usr/bin/dbus-send",
            runner=runner,
            environ={"DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus"},
        )

    def test_reads_manual_state_without_exposing_manual_proxy_fields(self):
        runner = _KdeRunner()
        client = self.make_client(runner)
        self.assertEqual(client.get_state(), DesktopProxyState("manual", ""))

    def test_sets_only_pac_script_and_proxy_type_and_notifies_kio(self):
        runner = _KdeRunner()
        client = self.make_client(runner)
        original_http = runner.values["httpProxy"]
        original_no_proxy = runner.values["NoProxyFor"]
        desired = DesktopProxyState("auto", "http://127.0.0.1:8082/proxy.pac")

        client.set_state(desired)

        self.assertEqual(client.get_state(), desired)
        self.assertEqual(runner.values["httpProxy"], original_http)
        self.assertEqual(runner.values["NoProxyFor"], original_no_proxy)
        write_keys = [
            call[0][call[0].index("--key") + 1]
            for call in runner.calls
            if call[0][0].endswith("kwriteconfig5")
        ]
        self.assertEqual(write_keys, ["Proxy Config Script", "ProxyType"])
        self.assertTrue(any(call[0][0].endswith("dbus-send") for call in runner.calls))

    def test_restores_manual_state_without_erasing_manual_values(self):
        runner = _KdeRunner()
        client = self.make_client(runner)
        original = client.get_state()
        client.set_state(DesktopProxyState("auto", "http://127.0.0.1:8082/proxy.pac"))
        client.set_state(original)
        self.assertEqual(client.get_state(), DesktopProxyState("manual", ""))
        self.assertEqual(runner.values["httpProxy"], "http://existing.proxy 8000")
        self.assertEqual(runner.values["NoProxyFor"], "localhost,127.0.0.1")

    def test_wpad_and_environment_modes_fail_closed_before_mutation(self):
        for proxy_type in ("3", "4"):
            runner = _KdeRunner()
            runner.values["ProxyType"] = proxy_type
            client = self.make_client(runner)
            with self.assertRaises(DesktopProxyError):
                client.get_state()
            self.assertFalse(any(call[0][0].endswith("kwriteconfig5") for call in runner.calls))

    def test_write_failure_is_reported(self):
        runner = _KdeRunner()
        runner.fail_write_key = "ProxyType"
        client = self.make_client(runner)
        with self.assertRaises(DesktopProxyError):
            client.set_state(DesktopProxyState("auto", "http://127.0.0.1/pac"))


if __name__ == "__main__":
    unittest.main()
