import json
import os
import tempfile
import unittest
from types import SimpleNamespace

from macos_backend import (
    AutoProxyState,
    MacOSBackend,
    ManualProxyState,
    NetworkService,
    NetworkSetupClient,
    NetworkSetupError,
)
from proxy_backend import ProxyBackend, ProxyBackendConfig

CONFIG = ProxyBackendConfig(
    pac_url="http://127.0.0.1:8082/proxy.pac",
    http_proxy_url="http://127.0.0.1:8080",
    no_proxy=("localhost", "127.0.0.1", "*.LOCAL"),
    socks_proxy_url="socks5://127.0.0.1:1080",
    upstream_http_proxy_url="http://upstream.example:9000",
    upstream_username="alice",
    upstream_password="secret",
)


class _FakeNetworkSetup:
    def __init__(self):
        self.services = {
            "Wi-Fi": {
                "service_enabled": True,
                "auto": AutoProxyState(False, ""),
                "web": {"enabled": True, "server": "proxy.example", "port": 8000, "authenticated": False},
                "secure_web": {"enabled": True, "server": "proxy.example", "port": 8000, "authenticated": False},
                "socks": {"enabled": False, "server": "old-socks.example", "port": 1088, "authenticated": False},
                "bypass": ("corp.example",),
            },
            "Ethernet": {
                "service_enabled": True,
                "auto": AutoProxyState(True, "http://old.example/proxy.pac"),
                "web": {"enabled": False, "server": "old-web.example", "port": 3128, "authenticated": False},
                "secure_web": {"enabled": False, "server": "old-secure.example", "port": 3129, "authenticated": False},
                "socks": {"enabled": True, "server": "old-socks.example", "port": 2080, "authenticated": False},
                "bypass": (),
            },
            "Disabled VPN": {
                "service_enabled": False,
                "auto": AutoProxyState(False, ""),
                "web": {"enabled": False, "server": "", "port": 0, "authenticated": False},
                "secure_web": {"enabled": False, "server": "", "port": 0, "authenticated": False},
                "socks": {"enabled": False, "server": "", "port": 0, "authenticated": False},
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
        return ManualProxyState(
            state["enabled"], state["server"], state["port"],
            bool(state.get("authenticated", False)),
        )

    def set_web_proxy(self, service, server, port, username="", password=""):
        self._maybe_fail("set_web_proxy", service)
        self.calls.append(
            ("set_web_proxy", service, server, int(port), username, password)
        )
        self.services[service]["web"].update(
            enabled=True,
            server=server,
            port=int(port),
            authenticated=bool(username and password),
        )

    def set_web_proxy_state(self, service, enabled):
        self._maybe_fail("set_web_proxy_state", service)
        self.calls.append(("set_web_proxy_state", service, enabled))
        self.services[service]["web"]["enabled"] = bool(enabled)

    def get_secure_web_proxy(self, service):
        self._maybe_fail("get_secure_web_proxy", service)
        self.calls.append(("get_secure_web_proxy", service))
        state = self.services[service]["secure_web"]
        return ManualProxyState(
            state["enabled"], state["server"], state["port"],
            bool(state.get("authenticated", False)),
        )

    def set_secure_web_proxy(
        self, service, server, port, username="", password=""
    ):
        self._maybe_fail("set_secure_web_proxy", service)
        self.calls.append(
            ("set_secure_web_proxy", service, server, int(port), username, password)
        )
        self.services[service]["secure_web"].update(
            enabled=True,
            server=server,
            port=int(port),
            authenticated=bool(username and password),
        )

    def set_secure_web_proxy_state(self, service, enabled):
        self._maybe_fail("set_secure_web_proxy_state", service)
        self.calls.append(("set_secure_web_proxy_state", service, enabled))
        self.services[service]["secure_web"]["enabled"] = bool(enabled)

    def get_socks_proxy(self, service):
        self._maybe_fail("get_socks_proxy", service)
        self.calls.append(("get_socks_proxy", service))
        state = self.services[service]["socks"]
        return ManualProxyState(
            state["enabled"], state["server"], state["port"],
            bool(state.get("authenticated", False)),
        )

    def set_socks_proxy(self, service, server, port):
        self._maybe_fail("set_socks_proxy", service)
        self.calls.append(("set_socks_proxy", service, server, int(port)))
        self.services[service]["socks"].update(
            enabled=True, server=server, port=int(port), authenticated=False
        )

    def set_socks_proxy_state(self, service, enabled):
        self._maybe_fail("set_socks_proxy_state", service)
        self.calls.append(("set_socks_proxy_state", service, enabled))
        self.services[service]["socks"]["enabled"] = bool(enabled)

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
        self.assertEqual(payload["schema_version"], 2)
        wifi = payload["services"]["Wi-Fi"]
        self.assertFalse(wifi["auto_proxy"]["enabled"])
        self.assertTrue(wifi["web_proxy"]["enabled"])
        self.assertFalse(wifi["socks_proxy"]["enabled"])
        self.assertEqual(wifi["socks_proxy"]["server"], "old-socks.example")

        self.assertFalse(self.client.services["Wi-Fi"]["auto"].enabled)
        self.assertEqual(
            self.client.services["Wi-Fi"]["web"],
            {
                "enabled": True,
                "server": "upstream.example",
                "port": 9000,
                "authenticated": True,
            },
        )
        self.assertEqual(
            self.client.services["Wi-Fi"]["secure_web"],
            {
                "enabled": True,
                "server": "upstream.example",
                "port": 9000,
                "authenticated": True,
            },
        )
        self.assertFalse(self.client.services["Wi-Fi"]["socks"]["enabled"])
        self.assertEqual(
            set(value.lower() for value in self.client.services["Wi-Fi"]["bypass"]),
            {"corp.example", "localhost", "127.0.0.1", "*.local"},
        )
        self.assertNotIn("Disabled VPN", payload["services"])

    def test_bypass_additions_are_capped_at_47_without_truncating_snapshot(self):
        original = tuple("base-%02d.example" % i for i in range(29))
        additions = tuple("extra-%02d.example" % i for i in range(30))
        self.client.services["Wi-Fi"]["bypass"] = original
        config = ProxyBackendConfig(
            pac_url=CONFIG.pac_url,
            http_proxy_url=CONFIG.http_proxy_url,
            no_proxy=additions,
            socks_proxy_url=CONFIG.socks_proxy_url,
            upstream_http_proxy_url=CONFIG.upstream_http_proxy_url,
            upstream_username=CONFIG.upstream_username,
            upstream_password=CONFIG.upstream_password,
        )

        self.assertTrue(self.backend.enable(config))

        applied = self.client.services["Wi-Fi"]["bypass"]
        self.assertEqual(len(applied), 47)
        self.assertEqual(applied[:29], original)
        self.assertEqual(applied[29:], additions[:18])
        self.assertNotIn(additions[18], applied)
        self.assertTrue(
            any("bypass additions limited by 47-entry safety ceiling for Wi-Fi" in line
                for line in self.logs)
        )

    def test_large_existing_bypass_is_preserved_without_rewrite(self):
        original = tuple("base-%02d.example" % i for i in range(48))
        self.client.services["Wi-Fi"]["bypass"] = original
        self.client.calls.clear()

        self.assertTrue(self.backend.enable(CONFIG))

        self.assertEqual(self.client.services["Wi-Fi"]["bypass"], original)
        self.assertNotIn(
            ("set_bypass_domains", "Wi-Fi", original),
            self.client.calls,
        )
        self.assertTrue(
            any("bypass additions limited by 47-entry safety ceiling for Wi-Fi" in line
                for line in self.logs)
        )

    def test_sync_no_proxy_does_not_rewrite_when_only_overflow_changes(self):
        original = tuple("base-%02d.example" % i for i in range(29))
        additions = tuple("extra-%02d.example" % i for i in range(18))
        self.client.services["Wi-Fi"]["bypass"] = original
        initial = ProxyBackendConfig(
            pac_url=CONFIG.pac_url,
            http_proxy_url=CONFIG.http_proxy_url,
            no_proxy=additions,
            socks_proxy_url=CONFIG.socks_proxy_url,
            upstream_http_proxy_url=CONFIG.upstream_http_proxy_url,
            upstream_username=CONFIG.upstream_username,
            upstream_password=CONFIG.upstream_password,
        )
        self.assertTrue(self.backend.enable(initial))
        self.assertEqual(len(self.client.services["Wi-Fi"]["bypass"]), 47)

        updated = ProxyBackendConfig(
            pac_url=CONFIG.pac_url,
            http_proxy_url=CONFIG.http_proxy_url,
            no_proxy=additions + ("overflow-a.example", "overflow-b.example"),
            socks_proxy_url=CONFIG.socks_proxy_url,
            upstream_http_proxy_url=CONFIG.upstream_http_proxy_url,
            upstream_username=CONFIG.upstream_username,
            upstream_password=CONFIG.upstream_password,
        )
        self.client.calls.clear()

        self.assertTrue(self.backend.sync_no_proxy(updated))

        wifi_mutations = [
            call for call in self.client.calls
            if call[0] == "set_bypass_domains" and call[1] == "Wi-Fi"
        ]
        self.assertEqual(wifi_mutations, [])
        self.assertEqual(len(self.client.services["Wi-Fi"]["bypass"]), 47)
        self.assertTrue(self.backend.is_enabled(updated))

    def test_direct_upstream_ownership_does_not_depend_on_networksetup_auth_flag(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.services["Wi-Fi"]["web"]["authenticated"] = False
        self.client.services["Wi-Fi"]["secure_web"]["authenticated"] = False

        self.assertTrue(self.backend.is_enabled(CONFIG))
        self.assertTrue(self.backend.disable_preflight())

    def test_enable_refuses_conflicting_live_localhost_pac_before_mutation(self):
        self.client.services["Wi-Fi"]["auto"] = AutoProxyState(
            True, "http://127.0.0.1:9999/proxy.pac"
        )
        backend = MacOSBackend(
            client=self.client,
            state_path=self.backup_path,
            logger=self.logs.append,
            local_pac_probe=lambda _url: True,
        )
        self.client.calls.clear()

        self.assertFalse(backend.enable(CONFIG))

        self.assertFalse(os.path.exists(self.backup_path))
        self.assertFalse(
            any(call[0].startswith("set_") for call in self.client.calls)
        )
        self.assertIn("conflicting localhost PAC is active", self.logs[-1])

    def test_enable_refuses_unavailable_localhost_pac_rollback_dependency(self):
        self.client.services["Wi-Fi"]["auto"] = AutoProxyState(
            True, "http://127.0.0.1:9999/proxy.pac"
        )
        backend = MacOSBackend(
            client=self.client,
            state_path=self.backup_path,
            logger=self.logs.append,
            local_pac_probe=lambda _url: False,
        )
        self.client.calls.clear()

        self.assertFalse(backend.enable(CONFIG))

        self.assertFalse(os.path.exists(self.backup_path))
        self.assertFalse(
            any(call[0].startswith("set_") for call in self.client.calls)
        )
        self.assertIn("saved localhost PAC backing is unavailable", self.logs[-1])

    def test_disable_preflight_refuses_missing_saved_localhost_pac(self):
        probe_ready = [True]
        self.client.services["Wi-Fi"]["auto"] = AutoProxyState(
            True, CONFIG.pac_url
        )
        backend = MacOSBackend(
            client=self.client,
            state_path=self.backup_path,
            logger=self.logs.append,
            local_pac_probe=lambda _url: probe_ready[0],
        )
        self.assertTrue(backend.enable(CONFIG))
        probe_ready[0] = False

        self.assertFalse(backend.disable_preflight())
        self.assertTrue(backend.restore_pending())
        self.assertTrue(backend.is_enabled(CONFIG))
        self.assertIn("saved localhost PAC is unavailable", self.logs[-1])

    def test_disable_preflight_accepts_dropped_url_for_disabled_pac(self):
        saved_url = "http://127.0.0.1:8082/proxy.pac"
        self.client.services["Wi-Fi"]["auto"] = AutoProxyState(False, saved_url)

        self.assertTrue(self.backend.enable(CONFIG))
        # macOS may normalize a disabled remembered PAC URL to (null) after a
        # network/wake transition. That is not a foreign active route.
        self.client.services["Wi-Fi"]["auto"] = AutoProxyState(False, "")

        self.assertTrue(self.backend.disable_preflight())
        self.assertTrue(self.backend.disable())
        self.assertFalse(self.backend.restore_pending())
        self.assertFalse(self.client.services["Wi-Fi"]["auto"].enabled)
        self.assertEqual(self.client.services["Wi-Fi"]["auto"].url, saved_url)

    def test_disable_preflight_refuses_foreign_manual_route_before_stop(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.services["Wi-Fi"]["web"]["server"] = "foreign.example"

        self.assertFalse(self.backend.disable_preflight())
        self.assertTrue(self.backend.restore_pending())
        self.assertTrue(self.client.services["Wi-Fi"]["secure_web"]["enabled"])
        self.assertIn("disable preflight refused", self.logs[-1])

    def test_disable_preflight_accepts_reachable_saved_localhost_pac(self):
        self.client.services["Wi-Fi"]["auto"] = AutoProxyState(
            True, CONFIG.pac_url
        )
        backend = MacOSBackend(
            client=self.client,
            state_path=self.backup_path,
            local_pac_probe=lambda _url: True,
        )
        self.assertTrue(backend.enable(CONFIG))

        self.assertTrue(backend.disable_preflight())

    def test_enable_routes_directly_via_upstream_and_disable_restores_all_proxy_states(self):
        original_web = dict(self.client.services["Wi-Fi"]["web"])
        original_secure = dict(self.client.services["Wi-Fi"]["secure_web"])
        original_socks = dict(self.client.services["Wi-Fi"]["socks"])

        self.assertTrue(self.backend.enable(CONFIG))

        self.assertEqual(
            self.client.services["Wi-Fi"]["web"],
            {
                "enabled": True,
                "server": "upstream.example",
                "port": 9000,
                "authenticated": True,
            },
        )
        self.assertEqual(
            self.client.services["Wi-Fi"]["secure_web"],
            {
                "enabled": True,
                "server": "upstream.example",
                "port": 9000,
                "authenticated": True,
            },
        )
        self.assertFalse(self.client.services["Wi-Fi"]["socks"]["enabled"])
        self.assertFalse(self.client.services["Wi-Fi"]["auto"].enabled)

        self.assertTrue(self.backend.disable())
        self.assertEqual(self.client.services["Wi-Fi"]["web"], original_web)
        self.assertEqual(self.client.services["Wi-Fi"]["secure_web"], original_secure)
        self.assertEqual(self.client.services["Wi-Fi"]["socks"], original_socks)

    def test_enable_disables_existing_pac_without_replacing_its_url(self):
        original_url = self.client.services["Ethernet"]["auto"].url
        self.assertTrue(self.backend.enable(CONFIG))

        self.assertEqual(self.client.services["Ethernet"]["auto"].url, original_url)
        self.assertFalse(self.client.services["Ethernet"]["auto"].enabled)
        self.assertNotIn(
            ("set_auto_proxy_url", "Ethernet", CONFIG.pac_url),
            self.client.calls,
        )

    def test_refresh_reasserts_only_owned_direct_route_and_preserves_backup(self):
        self.assertTrue(self.backend.enable(CONFIG))
        with open(self.backup_path, "rb") as stream:
            backup_before = stream.read()
        self.client.calls.clear()

        self.assertTrue(self.backend.refresh(CONFIG))

        mutations = [call for call in self.client.calls if call[0].startswith("set_")]
        self.assertCountEqual(
            mutations,
            [
                ("set_web_proxy", "Wi-Fi", "upstream.example", 9000, "alice", "secret"),
                ("set_secure_web_proxy", "Wi-Fi", "upstream.example", 9000, "alice", "secret"),
                ("set_web_proxy_state", "Wi-Fi", True),
                ("set_secure_web_proxy_state", "Wi-Fi", True),
                ("set_web_proxy", "Ethernet", "upstream.example", 9000, "alice", "secret"),
                ("set_secure_web_proxy", "Ethernet", "upstream.example", 9000, "alice", "secret"),
                ("set_web_proxy_state", "Ethernet", True),
                ("set_secure_web_proxy_state", "Ethernet", True),
            ],
        )
        self.assertFalse(
            any(
                call[0] in {
                    "set_auto_proxy_state",
                    "set_socks_proxy_state",
                    "set_bypass_domains",
                }
                for call in mutations
            )
        )
        with open(self.backup_path, "rb") as stream:
            self.assertEqual(stream.read(), backup_before)
        self.assertTrue(self.backend.is_enabled(CONFIG))

    def test_refresh_refuses_foreign_live_state_without_mutation(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.services["Wi-Fi"]["auto"] = AutoProxyState(
            True, "http://foreign.example/proxy.pac"
        )
        self.client.calls.clear()

        self.assertFalse(self.backend.refresh(CONFIG))

        self.assertFalse(
            any(call[0].startswith("set_") for call in self.client.calls)
        )
        self.assertEqual(
            self.client.services["Wi-Fi"]["auto"],
            AutoProxyState(True, "http://foreign.example/proxy.pac"),
        )
        self.assertTrue(self.backend.restore_pending())

    def test_refresh_refuses_changed_manual_route_without_mutation(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.services["Wi-Fi"]["web"]["server"] = "foreign.example"
        self.client.calls.clear()

        self.assertFalse(self.backend.refresh(CONFIG))

        self.assertFalse(any(call[0].startswith("set_") for call in self.client.calls))
        self.assertTrue(self.backend.restore_pending())


    def test_refresh_failure_never_disables_owned_direct_route(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.client.calls.clear()
        self.client.fail_once("set_secure_web_proxy", "Wi-Fi")

        self.assertFalse(self.backend.refresh(CONFIG))

        self.assertFalse(
            any(
                call[0] in {"set_web_proxy_state", "set_secure_web_proxy_state"}
                and call[2] is False
                for call in self.client.calls
            )
        )
        self.assertTrue(self.client.services["Wi-Fi"]["web"]["enabled"])
        self.assertTrue(self.client.services["Wi-Fi"]["secure_web"]["enabled"])
        self.assertTrue(self.backend.restore_pending())

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

    def test_disable_restores_enabled_snapshot_pac_and_manual_endpoints(self):
        original_auto = self.client.services["Ethernet"]["auto"]
        original_web = dict(self.client.services["Ethernet"]["web"])
        original_secure = dict(self.client.services["Ethernet"]["secure_web"])
        original_socks = dict(self.client.services["Ethernet"]["socks"])

        self.assertTrue(self.backend.enable(CONFIG))
        self.client.calls.clear()
        self.assertTrue(self.backend.disable())

        self.assertEqual(self.client.services["Ethernet"]["auto"], original_auto)
        self.assertEqual(self.client.services["Ethernet"]["web"], original_web)
        self.assertEqual(self.client.services["Ethernet"]["secure_web"], original_secure)
        self.assertEqual(self.client.services["Ethernet"]["socks"], original_socks)

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
        self.assertEqual(
            self.client.services["Ethernet"]["auto"],
            AutoProxyState(True, "http://old.example/proxy.pac"),
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
        self.assertEqual(self.client.services["Wi-Fi"]["web"]["server"], "foreign.example")

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
            dict(self.client.services["Wi-Fi"]["socks"]),
            self.client.services["Wi-Fi"]["bypass"],
        )
        original_ethernet = (
            self.client.services["Ethernet"]["auto"],
            dict(self.client.services["Ethernet"]["web"]),
            dict(self.client.services["Ethernet"]["secure_web"]),
            dict(self.client.services["Ethernet"]["socks"]),
            self.client.services["Ethernet"]["bypass"],
        )
        self.client.fail_once("set_auto_proxy_state", "Ethernet")

        self.assertFalse(self.backend.enable(CONFIG))
        self.assertFalse(self.backend.restore_pending())
        self.assertFalse(self.client.services["Wi-Fi"]["auto"].enabled)
        self.assertEqual(self.client.services["Wi-Fi"]["web"], original_wifi[1])
        self.assertEqual(self.client.services["Wi-Fi"]["secure_web"], original_wifi[2])
        self.assertEqual(self.client.services["Wi-Fi"]["socks"], original_wifi[3])
        self.assertEqual(self.client.services["Wi-Fi"]["bypass"], original_wifi[4])
        self.assertEqual(self.client.services["Ethernet"]["auto"], original_ethernet[0])
        self.assertEqual(self.client.services["Ethernet"]["web"], original_ethernet[1])
        self.assertEqual(
            self.client.services["Ethernet"]["secure_web"],
            original_ethernet[2],
        )
        self.assertEqual(
            self.client.services["Ethernet"]["socks"],
            original_ethernet[3],
        )
        self.assertEqual(
            self.client.services["Ethernet"]["bypass"],
            original_ethernet[4],
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
            socks_proxy_url=CONFIG.socks_proxy_url,
            upstream_http_proxy_url=CONFIG.upstream_http_proxy_url,
            upstream_username=CONFIG.upstream_username,
            upstream_password=CONFIG.upstream_password,
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
                socks_proxy_url=CONFIG.socks_proxy_url,
            ),
            ProxyBackendConfig(
                pac_url=CONFIG.pac_url,
                http_proxy_url="http://127.0.0.1:9999",
                no_proxy=CONFIG.no_proxy,
                socks_proxy_url=CONFIG.socks_proxy_url,
            ),
            ProxyBackendConfig(
                pac_url=CONFIG.pac_url,
                http_proxy_url=CONFIG.http_proxy_url,
                no_proxy=CONFIG.no_proxy,
                socks_proxy_url="socks5://127.0.0.1:9999",
            ),
        )
        calls_before = len(self.client.calls)
        for config in variants:
            with self.subTest(config=config):
                self.assertFalse(self.backend.sync_no_proxy(config))
        self.assertEqual(len(self.client.calls), calls_before)

    def test_authenticated_manual_baseline_is_refused_before_mutation(self):
        self.client.services["Wi-Fi"]["web"]["authenticated"] = True
        calls_before = len(self.client.calls)

        self.assertFalse(self.backend.enable(CONFIG))
        self.assertFalse(self.backend.restore_pending())
        mutations = [
            call for call in self.client.calls[calls_before:]
            if call[0].startswith("set_")
        ]
        self.assertEqual(mutations, [])

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

    def test_socks_proxy_getter_and_setter_use_networksetup_contract(self):
        calls = []

        def runner(argv, **kwargs):
            calls.append(argv)
            if argv[1] == "-getsocksfirewallproxy":
                return SimpleNamespace(
                    returncode=0,
                    stdout=(
                        "Enabled: Yes\n"
                        "Server: 127.0.0.1\n"
                        "Port: 11080\n"
                        "Authenticated Proxy Enabled: 0\n"
                    ),
                    stderr="",
                )
            return SimpleNamespace(returncode=0, stdout="", stderr="")

        client = NetworkSetupClient(runner=runner)
        self.assertEqual(
            client.get_socks_proxy("Wi-Fi"),
            ManualProxyState(True, "127.0.0.1", 11080, False),
        )
        client.set_socks_proxy("Wi-Fi", "127.0.0.1", 11080)
        client.set_socks_proxy_state("Wi-Fi", True)

        self.assertIn(
            [
                "/usr/sbin/networksetup",
                "-setsocksfirewallproxy",
                "Wi-Fi",
                "127.0.0.1",
                "11080",
                "off",
            ],
            calls,
        )
        self.assertIn(
            [
                "/usr/sbin/networksetup",
                "-setsocksfirewallproxystate",
                "Wi-Fi",
                "on",
            ],
            calls,
        )

    def test_manual_proxy_setters_use_unauthenticated_local_route(self):
        calls = []

        def runner(argv, **kwargs):
            calls.append(argv)
            return SimpleNamespace(returncode=0, stdout="", stderr="")

        client = NetworkSetupClient(runner=runner)
        client.set_web_proxy("Wi-Fi", "127.0.0.1", 18080)
        client.set_secure_web_proxy("Wi-Fi", "127.0.0.1", 18080)

        self.assertEqual(
            calls,
            [
                ["/usr/sbin/networksetup", "-setwebproxy", "Wi-Fi", "127.0.0.1", "18080", "off"],
                ["/usr/sbin/networksetup", "-setsecurewebproxy", "Wi-Fi", "127.0.0.1", "18080", "off"],
            ],
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