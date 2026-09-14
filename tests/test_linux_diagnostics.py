import json
import os
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import linux_diagnostics as diag
from linux_backend import ActiveConnection, NetworkManagerProxyState
from linux_networkmanager_preflight import NetworkManagerPreflight, PreflightStatus
from linux_runtime import LinuxRuntimeEnvironment


def _canary(label):
    # Assemble support-bundle leak markers at runtime so repository secret scans
    # do not need static credential-like fixtures to validate redaction.
    return "-".join(("APL", "LNX", "006", str(label), "canary", "7Yw3Jp"))


class FakeCore:
    APP_VERSION = "0.2.3"
    ENGINEERING_MILESTONE = "P0.2"
    _PROXY_ENV_NAMES = ("HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY")

    def __init__(self, root):
        self.root = Path(root)
        self._settings = {
            "config_version": 1,
            "local_http_port": 18080,
            "local_socks_port": 11080,
            "local_pac_port": 18082,
            "pac_path": "/proxy.pac",
            "upstream": [{
                "host": "proxy.example.test",
                "port": 3128,
                "username": "alice",
                "password": _canary("settings"),
            }],
        }

    def install_dir(self):
        return str(self.root / "install")

    def data_dir(self):
        return str(self.root / "data")

    def settings_path(self):
        return str(self.root / "data" / "proxy_settings.json")

    def settings_backup_path(self):
        return str(self.root / "data" / "proxy_settings.lastgood.json")

    def config_recovery_path(self):
        return str(self.root / "data" / "config_recovery.json")

    def config_quarantine_dir(self):
        return str(self.root / "data" / "quarantine")

    def no_proxy_path(self):
        return str(self.root / "data" / "no_proxy.txt")

    def pid_path(self):
        return str(self.root / "data" / "proxy_core.pid")

    def log_path(self):
        return str(self.root / "data" / "proxy_core.log")

    def load_settings(self, migrate_legacy=True):
        self.assert_read_only = migrate_legacy is False
        return json.loads(json.dumps(self._settings))

    def load_no_proxy(self):
        return ["127.0.0.1", "localhost", "internal.example.test"]

    def is_running(self):
        return False

    def system_proxy_enabled(self):
        return False

    def network_restore_pending(self):
        return False

    def backend_operational_view(self):
        return {"state": "ready", "can_enable": True, "message": "ready"}

    def resolved_backend_config(self, settings):
        return SimpleNamespace(
            pac_url="http://127.0.0.1:18082/proxy.pac",
            http_proxy_url="http://127.0.0.1:18080",
            no_proxy=("127.0.0.1", "localhost", "internal.example.test"),
        )

    def structured_log(self, *args, **kwargs):
        return True


class FakeNetworkManagerClient:
    mutations = []

    def __init__(self, binary=None):
        self.binary = binary

    def list_active_connections(self):
        return (
            ActiveConnection("11111111-1111-1111-1111-111111111111", "ethernet", "eth0"),
            ActiveConnection("22222222-2222-2222-2222-222222222222", "vpn", "tun0"),
        )

    def get_proxy(self, uuid):
        return NetworkManagerProxyState(
            "auto",
            False,
            "http://127.0.0.1:18082/proxy.pac?access_token=%s" % _canary("nm"),
            "",
        )

    def set_proxy(self, *args, **kwargs):
        self.mutations.append(("set_proxy", args, kwargs))
        raise AssertionError("diagnostics must not mutate NetworkManager")

    def reapply(self, *args, **kwargs):
        self.mutations.append(("reapply", args, kwargs))
        raise AssertionError("diagnostics must not mutate NetworkManager")


class LinuxDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        FakeNetworkManagerClient.mutations = []

    @staticmethod
    def _runtime():
        return LinuxRuntimeEnvironment(
            distro_id="astra",
            id_like=("debian",),
            name="Astra Linux",
            pretty_name="Astra Linux Special Edition",
            version_id="1.8",
            version_codename="",
            variant="",
            variant_id="",
            astra_version="1.8",
            kernel_release="6.1-test",
            architecture="x86_64",
            desktop_environment="FLY",
            session_type="x11",
            nmcli_path="/usr/bin/nmcli",
            is_astra=True,
            is_debian_family=True,
            network_manager_client_available=True,
        )

    def _preflight(self):
        runtime = self._runtime()
        return NetworkManagerPreflight(
            runtime=runtime,
            status=PreflightStatus.READY,
            nmcli_version="1.42.4",
            networkmanager_state="connected",
            connectivity="full",
            active_connection_uuids=("11111111-1111-1111-1111-111111111111",),
            supported_active_connection_uuids=("11111111-1111-1111-1111-111111111111",),
            proxy_setting_supported=True,
            modify_system_permission="yes",
            modify_own_permission="yes",
            reasons=(),
        )

    def _patch_environment(self, td, fake):
        rollback = Path(td) / "state" / "linux_proxy_backup.json"
        autostart = Path(td) / "config" / "autostart" / "arvectum-proxy-launcher.desktop"
        autostart_status = SimpleNamespace(
            enabled=True,
            managed=True,
            conflict=False,
            path=str(autostart),
            message="Автозапуск включён.",
        )
        return (
            patch.object(diag, "_is_linux", return_value=True),
            patch.object(diag, "core", fake),
            patch.object(diag, "detect_linux_runtime", return_value=self._runtime()),
            patch.object(diag, "detect_networkmanager_preflight", return_value=self._preflight()),
            patch.object(diag, "NetworkManagerClient", FakeNetworkManagerClient),
            patch.object(diag.linux_backend, "_default_backup_path", return_value=str(rollback)),
            patch.object(diag.linux_autostart, "autostart_path", return_value=autostart),
            patch.object(diag.linux_autostart, "status", return_value=autostart_status),
            patch.object(diag, "policykit_interaction_requested", return_value=False),
        )

    def _snapshot(self, td, fake):
        patches = self._patch_environment(td, fake)
        for item in patches:
            item.start()
        try:
            return diag.collect_snapshot()
        finally:
            for item in reversed(patches):
                item.stop()

    @staticmethod
    def _read_members(bundle):
        with zipfile.ZipFile(bundle, "r") as archive:
            return {name: archive.read(name) for name in archive.namelist()}

    def test_snapshot_contains_linux_astra_networkmanager_support_state(self):
        with tempfile.TemporaryDirectory() as td:
            fake = FakeCore(td)
            snapshot = self._snapshot(td, fake)

        self.assertEqual(snapshot["schema"], diag.SCHEMA)
        self.assertEqual(snapshot["collector_version"], diag.COLLECTOR_VERSION)
        self.assertTrue(snapshot["read_only"])
        runtime = snapshot["sections"]["runtime"]["data"]
        self.assertTrue(runtime["is_astra"])
        self.assertEqual(runtime["runtime_id"], "astra")
        preflight = snapshot["sections"]["networkmanager_preflight"]["data"]
        self.assertEqual(preflight["status"], "ready")
        self.assertEqual(preflight["networkmanager_state"], "connected")
        profiles = snapshot["sections"]["networkmanager_profiles"]["data"]["active"]
        self.assertEqual(len(profiles), 2)
        self.assertTrue(profiles[0]["supported"])
        self.assertFalse(profiles[1]["supported"])
        self.assertEqual(FakeNetworkManagerClient.mutations, [])
        self.assertTrue(fake.assert_read_only)

    def test_settings_summary_omits_credentials_and_redacts_nmcli_secret(self):
        with tempfile.TemporaryDirectory() as td:
            fake = FakeCore(td)
            snapshot = self._snapshot(td, fake)
            encoded = json.dumps(snapshot, ensure_ascii=False)

        self.assertNotIn(_canary("settings"), encoded)
        self.assertNotIn(_canary("nm"), encoded)
        self.assertNotIn('"username": "alice"', encoded)
        self.assertIn('"username_configured": true', encoded)
        self.assertIn('"password_configured": true', encoded)
        self.assertIn("[REDACTED]", encoded)
        self.assertIn("proxy.example.test", encoded)

    def test_bundle_allowlist_never_copies_raw_configuration_rollback_or_autostart(self):
        markers = {
            "settings": _canary("raw-settings"),
            "rollback": _canary("raw-rollback"),
            "autostart": _canary("raw-autostart"),
        }
        with tempfile.TemporaryDirectory() as td:
            fake = FakeCore(td)
            data = Path(fake.data_dir())
            data.mkdir(parents=True)
            Path(fake.log_path()).write_text("diagnostic line\n", encoding="utf-8")
            Path(fake.settings_path()).write_text(
                json.dumps({"password": markers["settings"]}), encoding="utf-8"
            )
            rollback = Path(td) / "state" / "linux_proxy_backup.json"
            rollback.parent.mkdir(parents=True)
            rollback.write_text(markers["rollback"], encoding="utf-8")
            autostart = Path(td) / "config" / "autostart" / "arvectum-proxy-launcher.desktop"
            autostart.parent.mkdir(parents=True)
            autostart.write_text(markers["autostart"], encoding="utf-8")
            output = Path(td) / "out" / "support.zip"

            patches = self._patch_environment(td, fake)
            for item in patches:
                item.start()
            try:
                result = Path(diag.create_support_bundle(str(output)))
            finally:
                for item in reversed(patches):
                    item.stop()

            members = self._read_members(result)
            joined = b"\n".join(members.values()).decode("utf-8", errors="replace")

        self.assertEqual(set(members), {"diagnostics.json", "logs/proxy_core.log"})
        for marker in markers.values():
            self.assertNotIn(marker, joined)

    def test_bundle_collapses_home_prefix_in_sanitized_logs(self):
        with tempfile.TemporaryDirectory() as td:
            fake = FakeCore(td)
            Path(fake.data_dir()).mkdir(parents=True)
            literal_home = os.path.abspath(os.path.expanduser("~"))
            Path(fake.log_path()).write_text(
                json.dumps({"event": "path-test", "fields": {"path": literal_home + "/private/file"}}) + "\n",
                encoding="utf-8",
            )
            output = Path(td) / "support.zip"
            patches = self._patch_environment(td, fake)
            for item in patches:
                item.start()
            try:
                diag.create_support_bundle(str(output))
            finally:
                for item in reversed(patches):
                    item.stop()
            payload = self._read_members(output)["logs/proxy_core.log"].decode("utf-8")

        self.assertNotIn(literal_home + os.sep, payload)
        self.assertIn("~/private/file", payload)

    def test_bundle_redacts_process_proxy_and_log_secrets(self):
        env_secret = _canary("env")
        log_secret = _canary("log")
        with tempfile.TemporaryDirectory() as td:
            fake = FakeCore(td)
            Path(fake.data_dir()).mkdir(parents=True)
            Path(fake.log_path()).write_text(
                "Authorization: Bearer %s\npassword=%s\n" % (log_secret, log_secret),
                encoding="utf-8",
            )
            output = Path(td) / "support.zip"
            patches = self._patch_environment(td, fake)
            for item in patches:
                item.start()
            try:
                with patch.dict(
                    os.environ,
                    {"HTTP_PROXY": "http://alice:%s@proxy.example.test:3128" % env_secret},
                    clear=True,
                ):
                    diag.create_support_bundle(str(output))
            finally:
                for item in reversed(patches):
                    item.stop()
            payload = b"\n".join(self._read_members(output).values()).decode("utf-8", errors="replace")

        self.assertNotIn(env_secret, payload)
        self.assertNotIn(log_secret, payload)
        self.assertIn("[REDACTED]", payload)
        self.assertIn("proxy.example.test", payload)

    def test_failed_section_is_redacted_and_does_not_abort_snapshot(self):
        marker = _canary("exception")

        def broken():
            raise RuntimeError("password=%s" % marker)

        with patch.object(diag, "_is_linux", return_value=True), patch.object(
            diag, "_SECTION_COLLECTORS", (("broken", broken),)
        ):
            snapshot = diag.collect_snapshot()

        encoded = json.dumps(snapshot, ensure_ascii=False)
        self.assertNotIn(marker, encoded)
        self.assertIn("[REDACTED]", encoded)
        self.assertFalse(snapshot["sections"]["broken"]["ok"])

    def test_non_linux_host_is_rejected(self):
        with patch.object(diag, "_is_linux", return_value=False):
            with self.assertRaises(RuntimeError):
                diag.collect_snapshot()
            with self.assertRaises(RuntimeError):
                diag.create_support_bundle("support.zip")

    def test_home_prefix_is_collapsed_in_display_paths(self):
        fake_home = os.path.expanduser("~")
        nested = os.path.join(fake_home, ".local", "state", "Arvectum", "ProxyLauncher")
        display = diag._display_path(nested)
        self.assertTrue(display.startswith("~" + os.sep) or display == "~")
        self.assertFalse(display.startswith(fake_home + os.sep))

    def test_bundle_write_is_atomic_and_leaves_no_temporary_zip(self):
        with tempfile.TemporaryDirectory() as td:
            fake = FakeCore(td)
            Path(fake.data_dir()).mkdir(parents=True)
            output = Path(td) / "nested" / "support.zip"
            patches = self._patch_environment(td, fake)
            for item in patches:
                item.start()
            try:
                result = Path(diag.create_support_bundle(str(output)))
            finally:
                for item in reversed(patches):
                    item.stop()

            self.assertTrue(result.is_file())
            self.assertFalse(any(result.parent.glob("*.tmp-*")))
            data = json.loads(self._read_members(result)["diagnostics.json"].decode("utf-8"))
            self.assertEqual(data["schema"], diag.SCHEMA)


if __name__ == "__main__":
    unittest.main()
