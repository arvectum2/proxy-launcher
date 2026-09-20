import json
import os
import tempfile
import unittest
from types import SimpleNamespace

from linux_backend import (
    ActiveConnection,
    LinuxBackend,
    NetworkManagerClient,
    NetworkManagerError,
    NetworkManagerProxyState,
)
from linux_desktop_proxy import DesktopProxyState
from proxy_backend import ProxyBackend, ProxyBackendConfig

CONFIG = ProxyBackendConfig(
    pac_url="http://127.0.0.1:8082/proxy.pac",
    http_proxy_url="http://127.0.0.1:8080",
    no_proxy=("localhost", "127.0.0.1", "*.LOCAL"),
)


class _FakeNetworkManager:
    def __init__(self):
        self.active = [
            ActiveConnection("11111111-1111-1111-1111-111111111111", "ethernet", "eth0"),
            ActiveConnection("22222222-2222-2222-2222-222222222222", "wifi", "wlan0"),
            ActiveConnection("33333333-3333-3333-3333-333333333333", "vpn", "tun0"),
        ]
        self.profiles = {
            "11111111-1111-1111-1111-111111111111": "ethernet",
            "22222222-2222-2222-2222-222222222222": "wifi",
            "33333333-3333-3333-3333-333333333333": "vpn",
        }
        self.proxy = {
            "11111111-1111-1111-1111-111111111111": NetworkManagerProxyState(
                "none", False, "", ""
            ),
            "22222222-2222-2222-2222-222222222222": NetworkManagerProxyState(
                "auto", True, "http://old.example/proxy.pac", ""
            ),
            "33333333-3333-3333-3333-333333333333": NetworkManagerProxyState(
                "auto", False, "http://vpn.example/proxy.pac", ""
            ),
        }
        self.calls = []
        self.failures = []
        self.before_set = None

    def fail_once(self, operation, identity):
        self.failures.append((operation, identity))

    def _maybe_fail(self, operation, identity):
        marker = (operation, identity)
        if marker in self.failures:
            self.failures.remove(marker)
            raise NetworkManagerError("injected %s failure for %s" % marker)

    def list_active_connections(self):
        self.calls.append(("list_active_connections",))
        return tuple(self.active)

    def list_connection_profiles(self):
        self.calls.append(("list_connection_profiles",))
        return dict(self.profiles)

    def get_proxy(self, uuid):
        self._maybe_fail("get_proxy", uuid)
        self.calls.append(("get_proxy", uuid))
        return self.proxy[uuid]

    def set_proxy(self, uuid, state):
        self._maybe_fail("set_proxy", uuid)
        if self.before_set is not None:
            self.before_set(uuid, state)
        self.calls.append(("set_proxy", uuid, state))
        self.proxy[uuid] = state

    def reapply(self, device):
        self._maybe_fail("reapply", device)
        self.calls.append(("reapply", device))


class _FakeDesktopProxy:
    backend_id = "gsettings"

    def __init__(self):
        self.state = DesktopProxyState("none", "")
        self.calls = []
        self.fail_next_set = False

    def get_state(self):
        self.calls.append(("get_state",))
        return self.state

    def set_state(self, state):
        self.calls.append(("set_state", state))
        if self.fail_next_set:
            self.fail_next_set = False
            raise RuntimeError("injected desktop proxy failure")
        self.state = state


class LinuxBackendTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.backup_path = os.path.join(self.tempdir.name, "linux_proxy_backup.json")
        self.client = _FakeNetworkManager()
        self.desktop = _FakeDesktopProxy()
        self.logs = []
        self.backend = LinuxBackend(
            client=self.client,
            state_path=self.backup_path,
            logger=self.logs.append,
            desktop_client=self.desktop,
        )

    def tearDown(self):
        self.tempdir.cleanup()

    def test_is_concrete_backend_with_stable_id(self):
        self.assertIsInstance(self.backend, ProxyBackend)
        self.assertEqual(self.backend.backend_id, "linux")
        self.assertFalse(self.backend.restore_pending())

    def test_enable_snapshots_before_mutation_and_ignores_vpn(self):
        backup_seen = []

        def before_set(uuid, state):
            backup_seen.append(os.path.exists(self.backup_path))

        self.client.before_set = before_set
        vpn_before = self.client.proxy["33333333-3333-3333-3333-333333333333"]

        self.assertTrue(self.backend.enable(CONFIG))
        self.assertTrue(all(backup_seen))
        self.assertTrue(self.backend.restore_pending())
        self.assertTrue(self.backend.is_enabled(CONFIG))

        with open(self.backup_path, "r", encoding="utf-8") as stream:
            payload = json.load(stream)
        self.assertEqual(payload["backend"], "linux")
        self.assertEqual(payload["schema_version"], 2)
        self.assertEqual(payload["desktop_proxy"]["backend"], "gsettings")
        self.assertEqual(
            payload["desktop_proxy"]["state"],
            {"mode": "none", "autoconfig_url": ""},
        )
        self.assertEqual(
            self.desktop.state,
            DesktopProxyState("auto", CONFIG.pac_url),
        )
        self.assertEqual(
            set(payload["connections"]),
            {
                "11111111-1111-1111-1111-111111111111",
                "22222222-2222-2222-2222-222222222222",
            },
        )
        desired = NetworkManagerProxyState("auto", False, CONFIG.pac_url, "")
        self.assertEqual(
            self.client.proxy["11111111-1111-1111-1111-111111111111"], desired
        )
        self.assertEqual(
            self.client.proxy["22222222-2222-2222-2222-222222222222"], desired
        )
        self.assertEqual(
            self.client.proxy["33333333-3333-3333-3333-333333333333"], vpn_before
        )

    def test_manual_desktop_route_is_replaced_by_apl_auto_and_restored(self):
        self.desktop.state = DesktopProxyState("manual", "http://saved.example/manual.pac")
        original = self.desktop.state

        self.assertTrue(self.backend.enable(CONFIG))
        self.assertEqual(
            self.desktop.state,
            DesktopProxyState("auto", CONFIG.pac_url),
        )

        self.assertTrue(self.backend.disable())
        self.assertEqual(self.desktop.state, original)

    def test_disable_restores_exact_profiles_and_is_idempotent(self):
        original = dict(self.client.proxy)
        original_desktop = self.desktop.state
        self.assertTrue(self.backend.enable(CONFIG))

        # Persistent Arvectum state must be restored even if one profile later
        # becomes inactive; only an active profile needs device reapply.
        self.client.active = [
            connection
            for connection in self.client.active
            if connection.uuid != "22222222-2222-2222-2222-222222222222"
        ]
        self.client.calls.clear()

        self.assertTrue(self.backend.disable())
        self.assertFalse(self.backend.restore_pending())
        self.assertEqual(self.desktop.state, original_desktop)
        for uuid in (
            "11111111-1111-1111-1111-111111111111",
            "22222222-2222-2222-2222-222222222222",
        ):
            self.assertEqual(self.client.proxy[uuid], original[uuid])
        self.assertIn(("reapply", "eth0"), self.client.calls)
        self.assertNotIn(("reapply", "wlan0"), self.client.calls)

        calls_before = len(self.client.calls)
        self.assertTrue(self.backend.disable())
        self.assertEqual(len(self.client.calls), calls_before)

    def test_foreign_proxy_change_prevents_destructive_disable(self):
        self.assertTrue(self.backend.enable(CONFIG))
        uuid = "11111111-1111-1111-1111-111111111111"
        self.client.proxy[uuid] = NetworkManagerProxyState(
            "auto", False, "http://foreign.example/proxy.pac", ""
        )
        second_before = self.client.proxy["22222222-2222-2222-2222-222222222222"]

        self.assertFalse(self.backend.disable())
        self.assertTrue(self.backend.restore_pending())
        self.assertEqual(
            self.client.proxy[uuid].pac_url,
            "http://foreign.example/proxy.pac",
        )
        self.assertEqual(
            self.client.proxy["22222222-2222-2222-2222-222222222222"],
            second_before,
        )

    def test_foreign_profile_type_change_prevents_disable(self):
        self.assertTrue(self.backend.enable(CONFIG))
        uuid = "11111111-1111-1111-1111-111111111111"
        self.client.profiles[uuid] = "bridge"
        self.assertFalse(self.backend.disable())
        self.assertTrue(self.backend.restore_pending())

    def test_partial_enable_failure_rolls_back_touched_profiles(self):
        original = dict(self.client.proxy)
        self.client.fail_once("reapply", "wlan0")

        self.assertFalse(self.backend.enable(CONFIG))
        self.assertFalse(self.backend.restore_pending())
        self.assertEqual(self.client.proxy, original)

    def test_failed_rollback_preserves_pending_evidence(self):
        self.client.fail_once("reapply", "wlan0")
        original_set_proxy = self.client.set_proxy
        first_uuid = "11111111-1111-1111-1111-111111111111"
        occurrences = {"first": 0}

        def fail_second_set(uuid, state):
            if uuid == first_uuid:
                occurrences["first"] += 1
                if occurrences["first"] == 2:
                    raise NetworkManagerError("injected rollback failure")
            return original_set_proxy(uuid, state)

        self.client.set_proxy = fail_second_set
        self.assertFalse(self.backend.enable(CONFIG))
        self.assertTrue(self.backend.restore_pending())

    def test_sync_no_proxy_updates_identity_without_nm_mutation(self):
        self.assertTrue(self.backend.enable(CONFIG))
        updated = ProxyBackendConfig(
            pac_url=CONFIG.pac_url,
            http_proxy_url=CONFIG.http_proxy_url,
            no_proxy=("localhost", "new.internal"),
        )
        self.client.calls.clear()

        self.assertTrue(self.backend.sync_no_proxy(updated))
        self.assertTrue(self.backend.is_enabled(updated))
        self.assertFalse(self.backend.is_enabled(CONFIG))
        self.assertFalse(
            any(call[0] in {"set_proxy", "reapply"} for call in self.client.calls)
        )
        with open(self.backup_path, "r", encoding="utf-8") as stream:
            payload = json.load(stream)
        self.assertEqual(
            set(payload["applied_config"]["no_proxy"]),
            {"localhost", "new.internal"},
        )

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
        for config in variants:
            with self.subTest(config=config):
                self.assertFalse(self.backend.sync_no_proxy(config))

    def test_kde_backend_identity_is_persisted_and_required_for_restore(self):
        self.desktop.backend_id = "kde"
        self.assertTrue(self.backend.enable(CONFIG))
        with open(self.backup_path, "r", encoding="utf-8") as stream:
            payload = json.load(stream)
        self.assertEqual(payload["desktop_proxy"]["backend"], "kde")

        self.desktop.backend_id = "gsettings"
        self.assertFalse(self.backend.disable())
        self.assertTrue(self.backend.restore_pending())

        self.desktop.backend_id = "kde"
        self.assertTrue(self.backend.disable())
        self.assertFalse(self.backend.restore_pending())

    def test_desktop_mixed_original_and_applied_fields_remain_recoverable(self):
        self.desktop.state = DesktopProxyState("manual", "")
        original_profiles = dict(self.client.proxy)
        self.assertTrue(self.backend.enable(CONFIG))

        # KDE/system proxy UIs can switch ProxyType back to the saved mode while
        # leaving Arvectum's PAC URL behind. Recovery must remove only this
        # Arvectum-owned residue instead of stranding the rollback evidence.
        self.desktop.state = DesktopProxyState("manual", CONFIG.pac_url)

        self.assertFalse(self.backend.is_enabled(CONFIG))
        self.assertTrue(self.backend.restore_pending())
        self.assertTrue(self.backend.disable())
        self.assertFalse(self.backend.restore_pending())
        self.assertEqual(self.desktop.state, DesktopProxyState("manual", ""))
        for uuid in (
            "11111111-1111-1111-1111-111111111111",
            "22222222-2222-2222-2222-222222222222",
        ):
            self.assertEqual(self.client.proxy[uuid], original_profiles[uuid])

    def test_desktop_inverse_mixed_state_is_also_recoverable(self):
        self.desktop.state = DesktopProxyState("manual", "http://saved.example/pac")
        self.assertTrue(self.backend.enable(CONFIG))
        self.desktop.state = DesktopProxyState("auto", "http://saved.example/pac")

        self.assertTrue(self.backend.disable())
        self.assertEqual(
            self.desktop.state,
            DesktopProxyState("manual", "http://saved.example/pac"),
        )

    def test_desktop_foreign_change_prevents_destructive_disable(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.desktop.state = DesktopProxyState(
            "auto", "http://foreign.example/proxy.pac"
        )
        before = dict(self.client.proxy)

        self.assertFalse(self.backend.disable())
        self.assertTrue(self.backend.restore_pending())
        self.assertEqual(self.client.proxy, before)
        self.assertEqual(
            self.desktop.state.autoconfig_url,
            "http://foreign.example/proxy.pac",
        )

    def test_desktop_enable_failure_rolls_back_networkmanager_and_desktop(self):
        original_profiles = dict(self.client.proxy)
        original_desktop = self.desktop.state
        self.desktop.fail_next_set = True

        self.assertFalse(self.backend.enable(CONFIG))
        self.assertFalse(self.backend.restore_pending())
        self.assertEqual(self.client.proxy, original_profiles)
        self.assertEqual(self.desktop.state, original_desktop)

    def test_disable_retry_accepts_already_restored_desktop_state(self):
        self.assertTrue(self.backend.enable(CONFIG))
        self.desktop.state = DesktopProxyState("none", "")

        self.assertTrue(self.backend.disable())
        self.assertFalse(self.backend.restore_pending())
        self.assertEqual(self.desktop.state, DesktopProxyState("none", ""))

    def test_legacy_v1_backup_remains_recoverable_without_desktop_mutation(self):
        self.assertTrue(self.backend.enable(CONFIG))
        with open(self.backup_path, "r", encoding="utf-8") as stream:
            payload = json.load(stream)
        payload["schema_version"] = 1
        payload.pop("desktop_proxy", None)
        with open(self.backup_path, "w", encoding="utf-8") as stream:
            json.dump(payload, stream)
        self.desktop.state = DesktopProxyState("manual", "http://foreign/pac")

        self.assertTrue(self.backend.is_enabled(CONFIG))
        self.assertTrue(self.backend.disable())
        self.assertEqual(
            self.desktop.state,
            DesktopProxyState("manual", "http://foreign/pac"),
        )

    def test_corrupt_existing_backup_fails_closed_without_mutation(self):
        with open(self.backup_path, "w", encoding="utf-8") as stream:
            stream.write("{not-json")
        self.client.calls.clear()

        self.assertFalse(self.backend.enable(CONFIG))
        self.assertTrue(self.backend.restore_pending())
        self.assertEqual(self.client.calls, [])

    def test_new_unowned_active_profile_makes_is_enabled_false(self):
        self.assertTrue(self.backend.enable(CONFIG))
        uuid = "44444444-4444-4444-4444-444444444444"
        self.client.profiles[uuid] = "wifi"
        self.client.proxy[uuid] = NetworkManagerProxyState("none", False, "", "")
        self.client.active.append(ActiveConnection(uuid, "wifi", "wlan1"))
        self.assertFalse(self.backend.is_enabled(CONFIG))

    def test_no_supported_active_profiles_fails_before_mutation(self):
        self.client.active = [
            ActiveConnection("33333333-3333-3333-3333-333333333333", "vpn", "tun0")
        ]
        self.client.calls.clear()
        self.assertFalse(self.backend.enable(CONFIG))
        self.assertFalse(self.backend.restore_pending())
        self.assertFalse(
            any(call[0] in {"set_proxy", "reapply"} for call in self.client.calls)
        )


class NetworkManagerClientTests(unittest.TestCase):
    def test_parses_active_profiles_and_proxy_values(self):
        def runner(argv, **kwargs):
            if "--fields" in argv and "UUID,TYPE,DEVICE" in argv:
                return SimpleNamespace(
                    returncode=0,
                    stdout=(
                        "11111111-1111-1111-1111-111111111111:ethernet:eth0\n"
                        "22222222-2222-2222-2222-222222222222:wifi:wlan0\n"
                    ),
                    stderr="",
                )
            if "--fields" in argv and "UUID,TYPE" in argv:
                return SimpleNamespace(
                    returncode=0,
                    stdout="11111111-1111-1111-1111-111111111111:ethernet\n",
                    stderr="",
                )
            if "--get-values" in argv:
                field = argv[argv.index("--get-values") + 1]
                values = {
                    "proxy.method": "auto\n",
                    "proxy.browser-only": "no\n",
                    "proxy.pac-url": "http://127.0.0.1:8082/proxy.pac\n",
                    "proxy.pac-script": "",
                }
                return SimpleNamespace(returncode=0, stdout=values[field], stderr="")
            return SimpleNamespace(returncode=0, stdout="", stderr="")

        client = NetworkManagerClient(runner=runner)
        self.assertEqual(
            client.list_active_connections(),
            (
                ActiveConnection(
                    "11111111-1111-1111-1111-111111111111", "ethernet", "eth0"
                ),
                ActiveConnection(
                    "22222222-2222-2222-2222-222222222222", "wifi", "wlan0"
                ),
            ),
        )
        self.assertEqual(
            client.list_connection_profiles(),
            {"11111111-1111-1111-1111-111111111111": "ethernet"},
        )
        self.assertEqual(
            client.get_proxy("11111111-1111-1111-1111-111111111111"),
            NetworkManagerProxyState(
                "auto", False, "http://127.0.0.1:8082/proxy.pac", ""
            ),
        )

    def test_terse_parser_handles_escaped_colon_in_device(self):
        def runner(argv, **kwargs):
            return SimpleNamespace(
                returncode=0,
                stdout="11111111-1111-1111-1111-111111111111:ethernet:eth\\:0\n",
                stderr="",
            )

        client = NetworkManagerClient(runner=runner)
        self.assertEqual(client.list_active_connections()[0].device, "eth:0")

    def test_nmcli_errors_are_fail_closed(self):
        def runner(argv, **kwargs):
            return SimpleNamespace(returncode=10, stdout="", stderr="not authorized")

        client = NetworkManagerClient(runner=runner)
        with self.assertRaises(NetworkManagerError):
            client.list_active_connections()


if __name__ == "__main__":
    unittest.main()