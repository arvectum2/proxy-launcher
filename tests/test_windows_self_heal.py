"""Windows PAC recovery and upstream failover regression tests."""
import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

import application_runtime
import local_proxy_transport
import proxy_core as core
import proxy_gui
import windows_system_proxy


class WindowsPacSelfHealTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.backup_path = Path(self.temp.name) / "proxy_internet_backup.json"
        self.saved = {
            "AutoConfigURL": {"exists": False, "value": None},
            "ProxyEnable": {"exists": True, "value": 0},
            "AutoDetect": {"exists": True, "value": 0},
            "ProxyServer": {"exists": True, "value": "corp:3128"},
            "ProxyOverride": {"exists": False, "value": None},
        }
        self.current = {k: dict(v) for k, v in self.saved.items()}
        self.backup_path.write_text(json.dumps(self.saved), encoding="utf-8")

    def _test_context(self, reads=None):
        return (
            mock.patch.object(core, "is_windows", return_value=True),
            mock.patch.object(core, "_internet_backup_path", return_value=str(self.backup_path)),
            mock.patch.object(core, "_read_internet_settings", side_effect=reads or [self.current, self.current]),
            mock.patch.object(core, "load_settings", return_value=core.DEFAULT_SETTINGS),
            mock.patch.object(core, "system_proxy_enabled", return_value=True),
            mock.patch.object(core, "_reg_set", return_value=True),
            mock.patch.object(core, "_refresh_internet"),
            mock.patch.object(core, "structured_log"),
        )

    def test_owned_missing_pac_is_restored_once(self):
        p = self._test_context()
        with p[0], p[1], p[2], p[3], p[4], p[5] as write, p[6] as refresh, p[7] as log:
            self.assertEqual(core.reassert_missing_owned_pac(threading.Event()), "restored")
        write.assert_called_once_with(
            "AutoConfigURL", core.pac_url(core.DEFAULT_SETTINGS), "REG_SZ"
        )
        refresh.assert_called_once()
        self.assertEqual(log.call_args.kwargs["result"], "restored")

    def test_do_not_overwrite_corporate_pac_or_manual_proxy_or_wpad(self):
        cases = (
            ("foreign_pac", {"AutoConfigURL": {"exists": True, "value": "http://corp/pac"}}),
            ("manual_proxy", {"ProxyEnable": {"exists": True, "value": 1}}),
            ("wpad", {"AutoDetect": {"exists": True, "value": 1}}),
            ("server_changed", {"ProxyServer": {"exists": True, "value": "other:9000"}}),
        )
        for label, edit in cases:
            with self.subTest(label=label):
                current = {k: dict(v) for k, v in self.current.items()}
                current.update(edit)
                p = self._test_context(reads=[current])
                with p[0], p[1], p[2], p[3], p[4], p[5] as write, p[6], p[7]:
                    self.assertEqual(core.reassert_missing_owned_pac(threading.Event()), "foreign")
                write.assert_not_called()

    def test_backup_with_old_corporate_pac_fails_closed(self):
        self.saved["AutoConfigURL"] = {"exists": True, "value": "http://corp/pac"}
        self.backup_path.write_text(json.dumps(self.saved), encoding="utf-8")
        p = self._test_context()
        with p[0], p[1], p[2], p[3], p[4], p[5] as write, p[6], p[7]:
            self.assertEqual(core.reassert_missing_owned_pac(), "foreign")
        write.assert_not_called()

    def test_registry_race_aborts_before_write(self):
        raced = {k: dict(v) for k, v in self.current.items()}
        raced["AutoConfigURL"] = {"exists": True, "value": "http://corp/pac"}
        p = self._test_context(reads=[self.current, raced])
        with p[0], p[1], p[2], p[3], p[4], p[5] as write, p[6], p[7]:
            self.assertEqual(core.reassert_missing_owned_pac(), "foreign")
        write.assert_not_called()

    def test_explicit_stop_or_missing_backup_never_writes(self):
        stop = threading.Event()
        stop.set()
        p = self._test_context()
        with p[0], p[1], p[2], p[3], p[4], p[5] as write, p[6], p[7]:
            self.assertEqual(core.reassert_missing_owned_pac(stop), "skipped")
        write.assert_not_called()
        self.backup_path.unlink()
        p = self._test_context()
        with p[0], p[1], p[2], p[3], p[4], p[5] as write, p[6], p[7]:
            self.assertEqual(core.reassert_missing_owned_pac(), "no_ownership")
        write.assert_not_called()

    def test_live_windows_worker_checks_every_20_seconds_and_stops(self):
        stop_event = mock.Mock()
        stop_event.wait.side_effect = [False, False, True]
        proxy = mock.Mock(_stop=stop_event)
        with mock.patch.object(application_runtime.sys, "platform", "win32"), \
             mock.patch.object(core, "system_proxy_enabled", side_effect=[False, True]), \
             mock.patch.object(core, "reassert_missing_owned_pac", return_value="restored") as repair:
            core._run_proxy_loop(proxy)
        repair.assert_called_once_with(stop_event)
        self.assertEqual(
            stop_event.wait.call_args_list,
            [mock.call(application_runtime.WINDOWS_PAC_POLL_SECONDS)] * 3,
        )


class CircuitBreakerTests(unittest.TestCase):
    def settings(self):
        return {"upstream": [
            {"host": "one.test", "port": 8000, "username": "one", "password": "hidden"}
        ]}

    def test_3_failures_cool_down_and_probe_recovers(self):
        engine = core.ProxyCore(self.settings())
        broken = mock.Mock()
        broken.connect.side_effect = TimeoutError("unreachable")
        good = mock.Mock()
        good.recv.return_value = b"HTTP/1.1 200 OK\r\n\r\n"
        with mock.patch.object(core, "is_windows", return_value=False), \
             mock.patch.object(local_proxy_transport.socket, "socket",
                               side_effect=[broken, broken, broken, good]) as sockets, \
             mock.patch.object(core, "structured_log"):
            for _ in range(3):
                self.assertEqual(engine._open_upstream_tunnel("example.com", 443), (None, b""))
            self.assertEqual(engine._open_upstream_tunnel("example.com", 443), (None, b""))
            self.assertEqual(sockets.call_count, 3)
            # After the cooldown, the first successful request is a half-open probe.
            engine._retry_after[0] = 0
            stream, response = engine._open_upstream_tunnel("example.com", 443)
        self.assertIs(stream, good)
        self.assertIn(b"200", response)
        self.assertEqual(engine._retry_after[0], 0)
        self.assertEqual(engine._failures[0], 0)

    def test_fallback_uses_second_server_while_first_is_quarantined(self):
        settings = self.settings()
        settings["upstream"].append({"host": "two.test", "port": 8001, "username": "two", "password": "hidden"})
        engine = core.ProxyCore(settings)
        engine._retry_after[0] = local_proxy_transport.time.monotonic() + 40
        good = mock.Mock()
        good.recv.return_value = b"HTTP/1.1 200 OK\r\n\r\n"
        with mock.patch.object(core, "is_windows", return_value=False), \
             mock.patch.object(local_proxy_transport.socket, "socket", return_value=good), \
             mock.patch.object(core, "structured_log"):
            stream, _ = engine._open_upstream_tunnel("example.com", 443)
        self.assertIs(stream, good)
        good.connect.assert_called_once_with(("two.test", 8001))

    def test_health_file_rejects_stale_or_previous_worker(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / local_proxy_transport.HEALTH_FILENAME
            path.write_text(json.dumps({"pid": 123, "status": "healthy", "updated": 1}), encoding="utf-8")
            with mock.patch.object(core, "is_windows", return_value=True), \
                 mock.patch.object(core, "runtime_dir", return_value=td), \
                 mock.patch.object(core, "_read_pid", return_value={"pid": 123}):
                self.assertEqual(core.read_transport_health(), "unknown")
            with mock.patch.object(core, "is_windows", return_value=True), \
                 mock.patch.object(core, "runtime_dir", return_value=td), \
                 mock.patch.object(core, "_read_pid", return_value={"pid": 456}):
                self.assertEqual(core.read_transport_health(), "unknown")


class HonestStatusTests(unittest.TestCase):
    def test_error_state_is_not_connected(self):
        for status in ("unavailable", "degraded", "unknown"):
            with self.subTest(status=status):
                v = proxy_gui._final_status_view(
                    True, True, False, False, False, transport_health=status
                )
                self.assertNotEqual(v["key"], "active")
                self.assertTrue(v["can_off"])
        healthy = proxy_gui._final_status_view(
            True, True, False, False, False, transport_health="healthy"
        )
        self.assertEqual(healthy["key"], "active")


if __name__ == "__main__":
    unittest.main()
