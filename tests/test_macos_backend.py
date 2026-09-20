import json
import os
import tempfile
import unittest
from types import SimpleNamespace

from proxy_backend import ProxyBackend, ProxyBackendConfig
from macos_backend import (
    AutoProxyState,
    MacOSBackend,
    ManualProxyState,
    NetworkService,
    NetworkSetupClient,
    NetworkSetupError,
)


CONFIG = ProxyBackendConfig(
    pac_url="http://127.0.0.1:8082/proxy.pac",
    http_proxy_url="http://127.0.0.1:8080",
    no_proxy=("localhost", "127.0.0.1", "*.LOCAL"),
)


class _FakeNetworkSetup:
    def __init__(self):
        self.services = {
            "Wi-Fi": {
                "service_enabled": True,
                "auto": AutoProxyState(False, ""),
                "web": {"enabled": True, "server": "proxy.example", "port": 8000},
                "secure_web": {"enabled": True, "server": "proxy.example", "port": 8000},
                "bypass": ("corp.example",),
            },
            "Ethernet": {
                "service_enabled": True,
                "auto": AutoProxyState(True, "http://old.example/proxy.pac"),
                "web": {"enabled": False, "server": "old-web.example", "port": 3128},
                "secure_web": {"enabled": False, "server": "old-secure.example", "port": 3129},
                "bypass": (),
            },
            "Disabled VPN": {
                "service_enabled": False,
                "auto": AutoProxyState(False, ""),
                "web": {"enabled": False, "server": "", "port": 0},
                "secure_web": {"enabled": False, "server": "", "port": 0},
                "bypass": ("vpn.internal",),
            },
        }
        self.calls = []
        self.failures = []

    def fail_once(self, operation, service):
        self.failures.append((operation, service))

    def _maybe_fail(self, operation, service):
        marker = (operation, service)
        if marker in self.failures:
            self.failures.remove(marker)
            raise NetworkSetupError("injected %s failure for %s" % marker)

    def list_services(self):
        self.calls.append(("list_services",))
        return tuple(
            NetworkService(name=name, enabled=state["service_enabled"])
            for name, state in self.services.items()
        )

    def get_auto_proxy(self, service):
        self._maybe_fail("get_auto_proxy", service)
        self.calls.append(("get_auto_proxy", service))
        return self.services[service]["auto"]

    def set_auto_proxy_url(self, service, url):
        self._maybe_fail("set_auto_proxy_url", service)
        self.calls.append(("set_auto_proxy_url", service, url))
        self.services[service]["auto"] = AutoProxyState(True, url)

    def set_auto_proxy_state(self, service, enabled):
        self._maybe_fail("set_auto_proxy_state", service)
        self.calls.append(("set_auto_proxy_state", service, enabled))
        current = self.services[service]["auto"]
        self.services[service]["auto"] = AutoProxyState(enabled, current.url)

    def get_web_proxy(self, service):
        self._maybe_fail("get_web_proxy", service)
        self.calls.append(("get_web_proxy", service))
        state = self.services[service]["web"]
        return ManualProxyState(state["enabled"], state["server"], state["port"])

    def set_web_proxy_state(self, service, enabled):
        self._maybe_fail("set_web_proxy_state", service)
        self.calls.append(("set_web_proxy_state", service, enabled))
        self.services[service]["web"]["enabled"] = bool(enabled)

    def get_secure_web_proxy(self, service):
        self._maybe_fail("get_secure_web_proxy", service)
        self.calls.append(("get_secure_web_proxy", service))
        state = self.services[service]["secure_web"]
        return ManualProxyState(state["enabled"], state["server"], state["port"])

    def set_secure_web_proxy_state(self, service, enabled):
        self._maybe_fail("set_secure_web_proxy_state", service)
        self.calls.append(("set_secure_web_proxy_state", service, enabled))
        self.services[service]["secure_web"]["enabled"] = bool(enabled)

    def get_bypass_domains(self, service):
        self._maybe_fail("get_bypass_domains", service)
        self.calls.append(("get_bypass_domains", service))
        return self.services[service]["bypass"]

    def set_bypass_domains(self, service, domains):
        self._maybe_fail("set_bypass_domains", service)
        values = tuple(domains)
        self.calls.append(("set_bypass_domains", service, values))
        self.services[service]["bypass"] = values


class MacOSBackendTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.backup_path = os.path.join(self.tempdir.name, "macos_proxy_backup.json")
        self.client = _FakeNetworkSetup()
        self.logs = []
        self.backend = MacOSBackend(
            client=self.client,
            state_path=self.backup_path,
            logger=self.logs.append,
        )

    def tearDown(self):
        self.tempdir.cleanup()

    def test_is_concrete_proxy_backend_with_stable_id(self):
        self.assertIsInstance(self.backend, ProxyBackend)
        self.assertEqual(self.backend.backend_id, "macos")
        self.assertFalse(self.backend.restore_pending())

    def test_enable_snapshots_before_mutation_and_preserves_existing_bypass(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.assertTrue(os.path.exists(self.backup_path))
        self.assertTrue(self.backend.restore_pending())
        self.assertTrue(self.backend.is_enabled(CONFIG))

        with open(self.backup_path, "r", encoding="utf-8") as stream:
            payload = json.load(stream)
        self.assertEqual(payload["backend"], "macos")
        self.assertFalse(payload["services"]["Wi-Fi"]["auto_proxy"]["enabled"])
        self.assertTrue(payload["services"]["Wi-Fi"]["web_proxy"]["enabled"])
        self.assertEqual(
            payload["services"]["Wi-Fi"]["web_proxy"]["server"],
            "proxy.example",
        )
        self.assertTrue(payload["services"]["Wi-Fi"]["secure_web_proxy"]["enabled"])
        self.assertEqual(
            payload["services"]["Ethernet"]["auto_proxy"]["url"],
            "http://old.example/proxy.pac",
        )
        self.assertEqual(
            self.client.services["Wi-Fi"]["auto"],
            AutoProxyState(True, CONFIG.pac_url),
        )
        self.assertEqual(
            set(value.lower() for value in self.client.services["Wi-Fi"]["bypass"]),
            {"corp.example", "localhost", "127.0.0.1", "*.local"},
        )
        self.assertNotIn("Disabled VPN", payload["services"])
        self.assertEqual(self.client.services["Disabled VPN"]["bypass"], ("vpn.internal",))

    def test_enable_temporarily_disables_manual_http_https_and_disable_restores_them(self):
        original_web = dict(self.client.services["Wi-Fi"]["web"])
        original_secure = dict(self.client.services["Wi-Fi"]["secure_web"])

        self.assertTrue(self.backend.enable(CONFIG))

        self.assertFalse(self.client.services["Wi-Fi"]["web"]["enabled"])
        self.assertFalse(self.client.services["Wi-Fi"]["secure_web"]["enabled"])
        self.assertEqual(
            {
                "server": self.client.services["Wi-Fi"]["web"]["server"],
                "port": self.client.services["Wi-Fi"]["web"]["port"],
            },
            {"server": original_web["server"], "port": original_web["port"]},
        )
        self.assertEqual(
            {
                "server": self.client.services["Wi-Fi"]["secure_web"]["server"],
                "port": self.client.services["Wi-Fi"]["secure_web"]["port"],
            },
            {"server": original_secure["server"], "port": original_secure["port"]},
        )

        self.assertTrue(self.backend.disable())
        self.assertEqual(self.client.services["Wi-Fi"]["web"], original_web)
        self.assertEqual(self.client.services["Wi-Fi"]["secure_web"], original_secure)

    def test_enable_forces_pac_state_transition_after_replacing_active_url(self):
        self.assertTrue(self.client.services["Ethernet"]["auto"].enabled)
        self.assertEqual(
            self.client.services["Ethernet"]["auto"].url,
            "http://old.example/proxy.pac",
        )

        self.assertTrue(self.backend.enable(CONFIG))

        calls = self.client.calls
        url_i = calls.index(("set_auto_proxy_url", "Ethernet", CONFIG.pac_url))
        bypass_call = next(
            call for call in calls[url_i + 1:]
            if call[0:2] == ("set_bypass_domains", "Ethernet")
        )
        bypass_i = calls.index(bypass_call, url_i + 1)
        off_i = calls.index(("set_auto_proxy_state", "Ethernet", False), bypass_i + 1)
        on_i = calls.index(("set_auto_proxy_state", "Ethernet", True), off_i + 1)
        self.assertLess(url_i, bypass_i)
        self.assertLess(bypass_i, off_i)
        self.assertLess(off_i, on_i)

    def test_disable_restores_exact_snapshots_and_clears_ownership_evidence(self):
        original = {
            name: (state["auto"], state["bypass"])
            for name, state in self.client.services.items()
        }
        self.assertTrue(self.backend.enable(CONFIG))
        self.assertTrue(self.backend.disable())
        self.assertFalse(self.backend.restore_pending())
        self.assertFalse(os.path.exists(self.backup_path))
        # networksetup cannot clear an empty disabled PAC URL after another URL
        # has been written. Functional restoration therefore requires Enabled:
        # No plus the exact original bypass set; non-empty saved URLs stay exact.
        self.assertFalse(self.client.services["Wi-Fi"]["auto"].enabled)
        self.assertEqual(self.client.services["Wi-Fi"]["bypass"], original["Wi-Fi"][1])
        self.assertEqual(self.client.services["Ethernet"]["auto"], original["Ethernet"][0])
        self.assertEqual(self.client.services["Ethernet"]["bypass"], original["Ethernet"][1])

        calls_before = len(self.client.calls)
        self.assertTrue(self.backend.disable())
        self.assertEqual(len(self.client.calls), calls_before)

    def test_disable_refreshes_enabled_snapshot_after_restoring_url(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.calls.clear()

        self.assertTrue(self.backend.disable())

        calls = self.client.calls
        url_i = calls.index((
            "set_auto_proxy_url",
            "Ethernet",
            "http://old.example/proxy.pac",
        ))
        bypass_call = next(
            call for call in calls[url_i + 1:]
            if call[0:2] == ("set_bypass_domains", "Ethernet")
        )
        bypass_i = calls.index(bypass_call, url_i + 1)
        off_i = calls.index(("set_auto_proxy_state", "Ethernet", False), bypass_i + 1)
        on_i = calls.index(("set_auto_proxy_state", "Ethernet", True), off_i + 1)
        self.assertLess(url_i, bypass_i)
        self.assertLess(bypass_i, off_i)
        self.assertLess(off_i, on_i)

    def test_disable_skips_invalid_empty_setautoproxyurl_for_disabled_snapshot(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.calls.clear()

        self.assertTrue(self.backend.disable())

        self.assertNotIn(("set_auto_proxy_url", "Wi-Fi", ""), self.client.calls)
        self.assertFalse(self.client.services["Wi-Fi"]["auto"].enabled)
        self.assertEqual(self.client.services["Wi-Fi"]["bypass"], ("corp.example",))

    def test_disable_retry_completes_partial_restore(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.fail_once("set_auto_proxy_state", "Wi-Fi")

        self.assertFalse(self.backend.disable())
        self.assertTrue(self.backend.restore_pending())
        # Ethernet was already restored while Wi-Fi remains Arvectum-owned.
        self.assertEqual(
            self.client.services["Ethernet"]["auto"],
            AutoProxyState(True, "http://old.example/proxy.pac"),
        )
        self.assertEqual(
            self.client.services["Wi-Fi"]["auto"],
            AutoProxyState(True, CONFIG.pac_url),
        )

        self.assertTrue(self.backend.disable())
        self.assertFalse(self.backend.restore_pending())
        self.assertFalse(self.client.services["Wi-Fi"]["auto"].enabled)
        self.assertEqual(self.client.services["Wi-Fi"]["bypass"], ("corp.example",))

    def test_foreign_change_prevents_destructive_disable(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.services["Wi-Fi"]["auto"] = AutoProxyState(
            True, "http://foreign.example/proxy.pac"
        )
        ethernet_before = self.client.services["Ethernet"]["auto"]

        self.assertFalse(self.backend.disable())
        self.assertTrue(self.backend.restore_pending())
        self.assertEqual(
            self.client.services["Wi-Fi"]["auto"].url,
            "http://foreign.example/proxy.pac",
        )
        self.assertEqual(self.client.services["Ethernet"]["auto"], ethernet_before)

    def test_foreign_manual_proxy_endpoint_change_prevents_destructive_disable(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.services["Wi-Fi"]["web"]["server"] = "foreign.example"

        self.assertFalse(self.backend.disable())
        self.assertTrue(self.backend.restore_pending())
        self.assertEqual(
            self.client.services["Wi-Fi"]["auto"],
            AutoProxyState(True, CONFIG.pac_url),
        )
        self.assertFalse(self.client.services["Wi-Fi"]["web"]["enabled"])

    def test_disable_retry_completes_partial_manual_proxy_restore(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.fail_once("set_web_proxy_state", "Wi-Fi")

        self.assertFalse(self.backend.disable())
        self.assertTrue(self.backend.restore_pending())

        self.assertTrue(self.backend.disable())
        self.assertFalse(self.backend.restore_pending())
        self.assertTrue(self.client.services["Wi-Fi"]["web"]["enabled"])
        self.assertTrue(self.client.services["Wi-Fi"]["secure_web"]["enabled"])

    def test_partial_enable_failure_rolls_back_touched_services(self):
        original_wifi = (
            self.client.services["Wi-Fi"]["auto"],
            dict(self.client.services["Wi-Fi"]["web"]),
            dict(self.client.services["Wi-Fi"]["secure_web"]),
            self.client.services["Wi-Fi"]["bypass"],
        )
        original_ethernet = (
            self.client.services["Ethernet"]["auto"],
            dict(self.client.services["Ethernet"]["web"]),
            dict(self.client.services["Ethernet"]["secure_web"]),
            self.client.services["Ethernet"]["bypass"],
        )
        self.client.fail_once("set_auto_proxy_state", "Ethernet")

        self.assertFalse(self.backend.enable(CONFIG))
        self.assertFalse(self.backend.restore_pending())
        self.assertFalse(self.client.services["Wi-Fi"]["auto"].enabled)
        self.assertEqual(self.client.services["Wi-Fi"]["web"], original_wifi[1])
        self.assertEqual(self.client.services["Wi-Fi"]["secure_web"], original_wifi[2])
        self.assertEqual(self.client.services["Wi-Fi"]["bypass"], original_wifi[3])
        self.assertEqual(self.client.services["Ethernet"]["auto"], original_ethernet[0])
        self.assertEqual(self.client.services["Ethernet"]["web"], original_ethernet[1])
        self.assertEqual(
            self.client.services["Ethernet"]["secure_web"],
            original_ethernet[2],
        )
        self.assertEqual(
            self.client.services["Ethernet"]["bypass"],
            original_ethernet[3],
        )

    def test_is_enabled_fails_closed_when_manual_proxy_state_is_unreadable(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.fail_once("get_web_proxy", "Wi-Fi")

        self.assertFalse(self.backend.is_enabled(CONFIG))

    def test_sync_no_proxy_preserves_preexisting_entries_and_updates_ownership(self):
        self.assertTrue(self.backend.enable(CONFIG))
        updated = ProxyBackendConfig(
            pac_url=CONFIG.pac_url,
            http_proxy_url=CONFIG.http_proxy_url,
            no_proxy=("localhost", "new.internal"),
        )
        self.assertTrue(self.backend.sync_no_proxy(updated))
        self.assertTrue(self.backend.is_enabled(updated))
        self.assertFalse(self.backend.is_enabled(CONFIG))
        self.assertEqual(
            set(value.lower() for value in self.client.services["Wi-Fi"]["bypass"]),
            {"corp.example", "localhost", "new.internal"},
        )
        self.assertTrue(self.backend.disable())
        self.assertEqual(self.client.services["Wi-Fi"]["bypass"], ("corp.example",))

    def test_sync_refuses_pac_or_http_identity_change(self):
        self.assertTrue(self.backend.enable(CONFIG))
        variants = (
            ProxyBackendConfig(
                pac_url="http://127.0.0.1:9999/proxy.pac",
                http_proxy_url=CONFIG.http_proxy_url,
                no_proxy=CONFIG.no_proxy,
            ),
            ProxyBackendConfig(
                pac_url=CONFIG.pac_url,
                http_proxy_url="http://127.0.0.1:9999",
                no_proxy=CONFIG.no_proxy,
            ),
        )
        calls_before = len(self.client.calls)
        for config in variants:
            with self.subTest(config=config):
                self.assertFalse(self.backend.sync_no_proxy(config))
        self.assertEqual(len(self.client.calls), calls_before)

    def test_corrupt_existing_backup_fails_closed_without_mutation(self):
        os.makedirs(os.path.dirname(self.backup_path), exist_ok=True)
        with open(self.backup_path, "w", encoding="utf-8") as stream:
            stream.write("{not-json")
        calls_before = len(self.client.calls)

        self.assertFalse(self.backend.enable(CONFIG))
        self.assertTrue(self.backend.restore_pending())
        self.assertEqual(len(self.client.calls), calls_before)


class NetworkSetupClientParsingTests(unittest.TestCase):
    def test_parses_services_auto_proxy_and_empty_bypass(self):
        outputs = {
            "-listallnetworkservices": (
                0,
                "An asterisk (*) denotes that a network service is disabled.\n"
                "Wi-Fi\n*Bluetooth PAN\nEthernet\n",
            ),
            "-getautoproxyurl": (
                0,
                "URL: http://127.0.0.1:8082/proxy.pac\nEnabled: Yes\n",
            ),
            "-getproxybypassdomains": (
                0,
                "There aren't any bypass domains set on Wi-Fi.\n",
            ),
            "-getwebproxy": (
                0,
                "Enabled: Yes\nServer: proxy.example\nPort: 8000\nAuthenticated Proxy Enabled: 0\n",
            ),
            "-getsecurewebproxy": (
                0,
                "Enabled: No\nServer: secure.example\nPort: 8443\nAuthenticated Proxy Enabled: 0\n",
            ),
        }

        def runner(argv, **kwargs):
            returncode, stdout = outputs[argv[1]]
            return SimpleNamespace(returncode=returncode, stdout=stdout, stderr="")

        client = NetworkSetupClient(runner=runner)
        self.assertEqual(
            client.list_services(),
            (
                NetworkService("Wi-Fi", True),
                NetworkService("Bluetooth PAN", False),
                NetworkService("Ethernet", True),
            ),
        )
        self.assertEqual(
            client.get_auto_proxy("Wi-Fi"),
            AutoProxyState(True, "http://127.0.0.1:8082/proxy.pac"),
        )
        self.assertEqual(client.get_bypass_domains("Wi-Fi"), ())
        self.assertEqual(
            client.get_web_proxy("Wi-Fi"),
            ManualProxyState(True, "proxy.example", 8000),
        )
        self.assertEqual(
            client.get_secure_web_proxy("Wi-Fi"),
            ManualProxyState(False, "secure.example", 8443),
        )

    def test_networksetup_errors_are_fail_closed(self):
        def runner(argv, **kwargs):
            return SimpleNamespace(
                returncode=0,
                stdout="** Error: The parameters were not valid.\n",
                stderr="",
            )

        client = NetworkSetupClient(runner=runner)
        with self.assertRaises(NetworkSetupError):
            client.list_services()


if __name__ == "__main__":
    unittest.main()
