import json
import os
import tempfile
import unittest
from unittest import mock

import local_proxy_transport
import process_supervision
import proxy_core


class _FakeClient:
    def __init__(self, request):
        self._request = request
        self.sent = []
        self.closed = False

    def settimeout(self, _timeout):
        return None

    def recv(self, _size):
        data, self._request = self._request, b""
        return data

    def sendall(self, data):
        self.sent.append(data)

    def close(self):
        self.closed = True


class _FakeConnection:
    def __init__(self, response=b""):
        self.response = response
        self.sent = []
        self.closed = False

    def settimeout(self, _timeout):
        return None

    def sendall(self, data):
        self.sent.append(data)

    def recv(self, _size):
        data, self.response = self.response, b""
        return data

    def close(self):
        self.closed = True


class _ListenerSocket:
    def __init__(self):
        self.bind_calls = []
        self.closed = False

    def setsockopt(self, *_args):
        return None

    def bind(self, address):
        self.bind_calls.append(address)

    def listen(self, _backlog):
        return None

    def settimeout(self, _timeout):
        return None

    def shutdown(self, _how):
        return None

    def close(self):
        self.closed = True


class _UpstreamSocket:
    def __init__(self, fail=False):
        self.fail = fail
        self.connect_calls = []
        self.sent = []
        self.closed = False

    def settimeout(self, _timeout):
        return None

    def connect(self, address):
        self.connect_calls.append(address)
        if self.fail:
            raise OSError("network temporarily unavailable")

    def sendall(self, data):
        self.sent.append(data)

    def close(self):
        self.closed = True


class NetworkChangeTests(unittest.TestCase):
    """APL-REC-005 — network/interface changes must not corrupt recovery state."""

    def test_listeners_are_bound_only_to_loopback_not_physical_interface(self):
        listeners = [_ListenerSocket(), _ListenerSocket(), _ListenerSocket()]
        thread = mock.Mock()

        with mock.patch.object(local_proxy_transport.socket, "socket", side_effect=listeners), \
             mock.patch.object(local_proxy_transport.threading, "Thread", return_value=thread):
            core = proxy_core.ProxyCore(settings={
                "local_http_port": 18080,
                "local_socks_port": 11080,
                "local_pac_port": 18082,
                "pac_path": "/proxy.pac",
                "upstream": [],
            })
            ok, message = core.start()

        self.assertTrue(ok, message)
        self.assertEqual(
            [sock.bind_calls for sock in listeners],
            [[("127.0.0.1", 18080)], [("127.0.0.1", 11080)], [("127.0.0.1", 18082)]],
        )
        self.assertEqual(thread.start.call_count, 3)
        core.stop()

    def test_pac_health_probe_stays_on_loopback_after_interface_change(self):
        response = (
            b"HTTP/1.1 200 OK\r\n\r\n"
            b"function FindProxyForURL(url, host) { return 'PROXY 127.0.0.1:8080'; }"
        )
        connection = _FakeConnection(response=response)
        settings = {"local_pac_port": 18082, "pac_path": "/proxy.pac"}

        with mock.patch.object(
            process_supervision.socket, "create_connection", return_value=connection
        ) as connect:
            self.assertTrue(proxy_core._pac_healthy(settings))

        connect.assert_called_once_with(("127.0.0.1", 18082), timeout=1.0)
        self.assertIn(b"GET /proxy.pac", connection.sent[0])

    def test_existing_original_wininet_snapshot_survives_network_change(self):
        original = {
            "AutoConfigURL": {"exists": False, "value": None},
            "ProxyEnable": {"exists": True, "value": 1},
            "ProxyServer": {"exists": True, "value": "corp-proxy:3128"},
            "ProxyOverride": {"exists": True, "value": "<local>"},
            "AutoDetect": {"exists": True, "value": 1},
        }
        changed_network_view = {
            "AutoConfigURL": {"exists": True, "value": "http://127.0.0.1:8082/proxy.pac"},
            "ProxyEnable": {"exists": True, "value": 0},
            "ProxyServer": {"exists": True, "value": "wifi-proxy:8080"},
            "ProxyOverride": {"exists": False, "value": None},
            "AutoDetect": {"exists": True, "value": 0},
        }

        with tempfile.TemporaryDirectory() as tmp:
            backup = os.path.join(tmp, "proxy_internet_backup.json")
            with open(backup, "w", encoding="utf-8") as stream:
                json.dump(original, stream)

            with mock.patch.object(proxy_core, "_internet_backup_path", return_value=backup), \
                 mock.patch.object(
                     proxy_core, "_read_internet_settings", return_value=changed_network_view
                 ) as read_settings:
                self.assertTrue(proxy_core._save_internet_backup())

            read_settings.assert_not_called()
            with open(backup, "r", encoding="utf-8") as stream:
                self.assertEqual(json.load(stream), original)

    def test_inactive_manual_fields_do_not_change_exclusive_pac_ownership(self):
        settings = {"local_pac_port": 8082, "pac_path": "/proxy.pac"}
        values = {
            "AutoConfigURL": {
                "exists": True,
                "value": "http://127.0.0.1:8082/proxy.pac",
            },
            "ProxyEnable": {"exists": True, "value": 0},
            "ProxyServer": {"exists": True, "value": "new-network-proxy:8888"},
            "ProxyOverride": {"exists": True, "value": "*.intranet"},
            "AutoDetect": {"exists": True, "value": 0},
        }
        with mock.patch.object(proxy_core, "is_windows", return_value=True), \
             mock.patch.object(proxy_core, "load_settings", return_value=settings), \
             mock.patch.object(proxy_core, "_read_internet_settings", return_value=values):
            self.assertTrue(proxy_core.system_proxy_enabled())

    def test_upstream_host_is_not_pre_resolved_and_can_follow_dns_changes(self):
        settings = {
            "upstream": [
                {"host": "proxy.example.test", "port": 8000, "username": "u", "password": "p"}
            ]
        }
        with mock.patch.object(local_proxy_transport.socket, "getaddrinfo") as getaddrinfo, \
             mock.patch.object(local_proxy_transport.socket, "gethostbyname") as gethostbyname:
            core = proxy_core.ProxyCore(settings=settings)

        getaddrinfo.assert_not_called()
        gethostbyname.assert_not_called()
        self.assertEqual(core._upstreams[0][0:2], ("proxy.example.test", 8000))

    def test_direct_request_recovers_on_next_request_after_transient_network_loss(self):
        request = b"GET http://example.test/path HTTP/1.1\r\nHost: example.test\r\n\r\n"
        first = _FakeClient(request)
        second = _FakeClient(request)
        recovered_connection = _FakeConnection()
        core = proxy_core.ProxyCore(settings={"upstream": []})

        with mock.patch.object(proxy_core, "host_bypasses_proxy", return_value=True), \
             mock.patch.object(
                 local_proxy_transport.socket,
                 "create_connection",
                 side_effect=[OSError("adapter disconnected"), recovered_connection],
             ) as connect, \
             mock.patch.object(proxy_core.ProxyCore, "_relay") as relay:
            core._handle_http(first)
            core._handle_http(second)

        self.assertEqual(connect.call_count, 2)
        self.assertEqual(connect.call_args_list[0], mock.call(("example.test", 80), timeout=15))
        self.assertEqual(connect.call_args_list[1], mock.call(("example.test", 80), timeout=15))
        self.assertTrue(any(b"502" in chunk for chunk in first.sent))
        relay.assert_called_once()

    def test_upstream_request_reconnects_after_network_change_without_core_restart(self):
        request = b"GET http://example.test/path HTTP/1.1\r\nHost: example.test\r\n\r\n"
        first = _FakeClient(request)
        second = _FakeClient(request)
        failed_socket = _UpstreamSocket(fail=True)
        recovered_socket = _UpstreamSocket(fail=False)
        core = proxy_core.ProxyCore(settings={
            "upstream": [
                {"host": "proxy.example.test", "port": 8000, "username": "u", "password": "p"}
            ]
        })

        with mock.patch.object(proxy_core, "host_bypasses_proxy", return_value=False), \
             mock.patch.object(
                 local_proxy_transport.socket, "socket", side_effect=[failed_socket, recovered_socket]
             ) as socket_factory, \
             mock.patch.object(proxy_core.ProxyCore, "_relay") as relay:
            core._handle_http(first)
            core._handle_http(second)

        self.assertEqual(socket_factory.call_count, 2)
        self.assertEqual(failed_socket.connect_calls, [("proxy.example.test", 8000)])
        self.assertEqual(recovered_socket.connect_calls, [("proxy.example.test", 8000)])
        self.assertTrue(any(b"502" in chunk for chunk in first.sent))
        relay.assert_called_once_with(recovered_socket, second, core._stop)


if __name__ == "__main__":
    unittest.main()