import base64
import unittest
from unittest import mock

import local_proxy_transport
import proxy_core as core


class LocalProxyTransportExtractionTests(unittest.TestCase):
    def test_canonical_module_owns_transport_class(self):
        self.assertEqual(core.ProxyCore.__module__, "local_proxy_transport")
        self.assertEqual(core._SOCKS5_REPLY_BIND_ADDR, b"\x00\x00\x00\x00")

    def test_upstream_preparation_preserves_credentials_and_port_fallback(self):
        settings = {
            "upstream": [
                {"host": " proxy.test ", "port": "invalid", "username": "user", "password": "pass"},
                {"host": "", "port": 9000, "username": "ignored", "password": "ignored"},
            ]
        }
        engine = core.ProxyCore(settings)
        expected_token = base64.b64encode(b"user:pass").decode("ascii")
        self.assertEqual(engine._upstreams, [("proxy.test", 8000, expected_token)])

    def test_http_handler_resolves_canonical_routing_seam_dynamically(self):
        settings = {
            "local_http_port": 8080,
            "local_socks_port": 1080,
            "local_pac_port": 8082,
            "pac_path": "/proxy.pac",
            "upstream": [],
        }
        engine = core.ProxyCore(settings)
        client = mock.Mock()
        client.recv.return_value = (
            b"GET http://Example.TEST/path HTTP/1.1\r\n"
            b"Host: Example.TEST\r\nConnection: close\r\n\r\n"
        )
        direct = mock.Mock()

        with mock.patch.object(core, "_normalize_host", return_value="example.test") as normalize, \
             mock.patch.object(core, "host_bypasses_proxy", return_value=True) as bypass, \
             mock.patch.object(local_proxy_transport.socket, "create_connection", return_value=direct) as connect, \
             mock.patch.object(engine, "_relay") as relay:
            engine._handle_http(client)

        normalize.assert_called_once_with("Example.TEST")
        bypass.assert_called_once_with("example.test")
        connect.assert_called_once_with(("example.test", 80), timeout=15)
        direct.settimeout.assert_called_once_with(300)
        self.assertTrue(direct.sendall.call_args.args[0].startswith(b"GET /path HTTP/1.1"))
        relay.assert_called_once_with(direct, client, engine._stop)

    def test_pac_handler_resolves_build_pac_through_compatibility_seam(self):
        settings = {
            "local_http_port": 8080,
            "local_socks_port": 1080,
            "local_pac_port": 8082,
            "pac_path": "/custom.pac",
            "upstream": [],
        }
        engine = core.ProxyCore(settings)
        client = mock.Mock()
        client.recv.return_value = b"GET /custom.pac HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"

        with mock.patch.object(core, "build_pac", return_value="PAC-SLICE-5") as build_pac:
            engine._handle_pac(client)

        build_pac.assert_called_once_with()
        response = client.sendall.call_args.args[0]
        self.assertIn(b"HTTP/1.1 200 OK", response)
        self.assertIn(b"PAC-SLICE-5", response)
        self.assertIn(b"Content-Type: application/x-ns-proxy-autoconfig", response)

    def test_pac_handler_preserves_404_for_wrong_path(self):
        engine = core.ProxyCore({"pac_path": "/proxy.pac", "upstream": []})
        client = mock.Mock()
        client.recv.return_value = b"GET /wrong.pac HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        with mock.patch.object(core, "build_pac") as build_pac:
            engine._handle_pac(client)
        build_pac.assert_not_called()
        self.assertIn(b"404 Not Found", client.sendall.call_args.args[0])

    def test_relay_closes_idle_tunnel_after_300_awake_seconds(self):
        src = mock.Mock()
        dst = mock.Mock()
        stop = mock.Mock()
        stop.is_set.return_value = False

        engine = core.ProxyCore({"upstream": []})
        with mock.patch.object(
            local_proxy_transport.select,
            "select",
            return_value=([], [], []),
        ) as select_call, mock.patch.object(
            local_proxy_transport.time,
            "monotonic",
            side_effect=[100.0, 400.0, 400.0],
        ), mock.patch.object(
            local_proxy_transport.time,
            "time",
            side_effect=[1000.0, 1300.0],
        ), mock.patch.object(core, "structured_log") as log:
            engine._relay(src, dst, stop)

        select_call.assert_called_once_with([src, dst], [], [], 5.0)
        self.assertEqual(log.call_args.kwargs["termination_reason"], "idle_timeout")
        src.close.assert_called_once_with()
        dst.close.assert_called_once_with()

    def test_relay_retires_pre_sleep_tunnel_before_forwarding_post_wake_bytes(self):
        src = mock.Mock()
        dst = mock.Mock()
        stop = mock.Mock()
        stop.is_set.return_value = False

        engine = core.ProxyCore({"upstream": []})
        with mock.patch.object(
            local_proxy_transport.select,
            "select",
            return_value=([dst], [], []),
        ) as select_call, mock.patch.object(
            local_proxy_transport.time,
            "monotonic",
            side_effect=[100.0, 101.0, 101.0],
        ), mock.patch.object(
            local_proxy_transport.time,
            "time",
            side_effect=[1000.0, 1101.0],
        ), mock.patch.object(
            local_proxy_transport.sys,
            "platform",
            "darwin",
        ), mock.patch.object(core, "structured_log") as log:
            engine._relay(src, dst, stop)

        select_call.assert_called_once_with([src, dst], [], [], 5.0)
        self.assertEqual(engine.consume_resume_rebind_request(), 1101.0)
        dst.recv.assert_not_called()
        src.sendall.assert_not_called()
        self.assertEqual(
            log.call_args.kwargs["termination_reason"],
            "resume_after_sleep",
        )
        src.close.assert_called_once_with()
        dst.close.assert_called_once_with()

    def test_resume_rebind_request_is_coalesced_for_one_wake_burst(self):
        engine = core.ProxyCore({"upstream": []})
        with mock.patch.object(core, "structured_log") as log:
            first = engine._request_resume_rebind(detected_at=100.0)
            second = engine._request_resume_rebind(detected_at=101.0)
            first_detected = engine.consume_resume_rebind_request()
            third = engine._request_resume_rebind(detected_at=111.0)
            third_detected = engine.consume_resume_rebind_request()

        self.assertTrue(first)
        self.assertFalse(second)
        self.assertEqual(first_detected, 100.0)
        self.assertTrue(third)
        self.assertEqual(third_detected, 111.0)
        self.assertEqual(log.call_count, 2)
        self.assertEqual(
            log.call_args.kwargs["event"],
            "proxy.resume.transport_rebind_requested",
        )

    def test_non_macos_sleep_retires_tunnel_without_requesting_rebind(self):
        src = mock.Mock()
        dst = mock.Mock()
        stop = mock.Mock()
        stop.is_set.return_value = False
        engine = core.ProxyCore({"upstream": []})

        with mock.patch.object(
            local_proxy_transport.select,
            "select",
            return_value=([dst], [], []),
        ), mock.patch.object(
            local_proxy_transport.time,
            "monotonic",
            side_effect=[100.0, 101.0, 101.0],
        ), mock.patch.object(
            local_proxy_transport.time,
            "time",
            side_effect=[1000.0, 1101.0],
        ), mock.patch.object(
            local_proxy_transport.sys,
            "platform",
            "linux",
        ), mock.patch.object(core, "structured_log"):
            engine._relay(src, dst, stop)

        self.assertIsNone(engine.consume_resume_rebind_request())

    def test_relay_logs_byte_counts_and_client_eof(self):
        src = mock.Mock()
        dst = mock.Mock()
        stop = mock.Mock()
        stop.is_set.return_value = False
        src.recv.return_value = b"abc"
        dst.recv.side_effect = [b"xy", b""]

        engine = core.ProxyCore({"upstream": []})
        with mock.patch.object(
            local_proxy_transport.select,
            "select",
            side_effect=[([src], [], []), ([dst], [], []), ([dst], [], [])],
        ), mock.patch.object(core, "structured_log") as log:
            engine._relay(src, dst, stop)

        dst.sendall.assert_called_once_with(b"abc")
        src.sendall.assert_called_once_with(b"xy")
        close_call = log.call_args
        self.assertEqual(close_call.kwargs["event"], "proxy.relay.closed")
        self.assertEqual(close_call.kwargs["upstream_to_client_bytes"], 3)
        self.assertEqual(close_call.kwargs["client_to_upstream_bytes"], 2)
        self.assertEqual(close_call.kwargs["termination_reason"], "eof:client")

    def test_http_connect_fails_over_after_rejected_upstream(self):
        settings = {
            "upstream": [
                {"host": "proxy-one.test", "port": 8000, "username": "one", "password": "bad"},
                {"host": "proxy-two.test", "port": 8001, "username": "two", "password": "good"},
            ]
        }
        engine = core.ProxyCore(settings)
        client = mock.Mock()
        client.recv.return_value = (
            b"CONNECT chatgpt.com:443 HTTP/1.1\r\n"
            b"Host: chatgpt.com:443\r\n\r\n"
        )
        rejected = mock.Mock()
        rejected.recv.return_value = (
            b"HTTP/1.1 407 Proxy Authentication Required\r\n"
            b"Content-Length: 0\r\n\r\n"
        )
        accepted = mock.Mock()
        accepted.recv.return_value = (
            b"HTTP/1.1 200 Connection Established\r\n\r\n"
        )

        with mock.patch.object(core, "_normalize_host", return_value="chatgpt.com"), \
             mock.patch.object(core, "host_bypasses_proxy", return_value=False), \
             mock.patch.object(local_proxy_transport.socket, "socket", side_effect=[rejected, accepted]), \
             mock.patch.object(engine, "_relay") as relay:
            engine._handle_http(client)

        rejected.close.assert_called()
        accepted.connect.assert_called_once_with(("proxy-two.test", 8001))
        self.assertIn(
            b"HTTP/1.1 200 Connection Established",
            b"".join(call.args[0] for call in client.sendall.call_args_list),
        )
        relay.assert_called_once_with(accepted, client, engine._stop)

    def test_http_connect_preserves_client_headers_for_upstream_proxy(self):
        settings = {
            "upstream": [
                {"host": "proxy.test", "port": 8000, "username": "user", "password": "pass"},
            ]
        }
        engine = core.ProxyCore(settings)
        client = mock.Mock()
        client.recv.return_value = (
            b"CONNECT chatgpt.com:443 HTTP/1.1\r\n"
            b"Host: chatgpt.com:443\r\n"
            b"Proxy-Connection: keep-alive\r\n"
            b"User-Agent: Safari-Test\r\n"
            b"Proxy-Authorization: Basic stale-client-token\r\n\r\n"
        )
        accepted = mock.Mock()
        accepted.recv.return_value = b"HTTP/1.1 200 Connection Established\r\n\r\n"

        with mock.patch.object(core, "_normalize_host", return_value="chatgpt.com"), \
             mock.patch.object(core, "host_bypasses_proxy", return_value=False), \
             mock.patch.object(local_proxy_transport.socket, "socket", return_value=accepted), \
             mock.patch.object(engine, "_relay"):
            engine._handle_http(client)

        sent = b"".join(call.args[0] for call in accepted.sendall.call_args_list)
        self.assertIn(b"CONNECT chatgpt.com:443 HTTP/1.1\r\n", sent)
        self.assertIn(b"Host: chatgpt.com:443\r\n", sent)
        self.assertIn(b"Proxy-Connection: keep-alive\r\n", sent)
        self.assertIn(b"User-Agent: Safari-Test\r\n", sent)
        self.assertNotIn(b"stale-client-token", sent)
        token = base64.b64encode(b"user:pass")
        self.assertIn(b"Proxy-Authorization: Basic " + token + b"\r\n", sent)

    def test_http_connect_reads_split_headers_before_opening_tunnel(self):
        settings = {
            "upstream": [
                {"host": "proxy.test", "port": 8000, "username": "user", "password": "pass"},
            ]
        }
        engine = core.ProxyCore(settings)
        client = mock.Mock()
        client.recv.side_effect = [
            b"CONNECT chatgpt.com:443 HTTP/1.1\r\nHost: chatgpt.com:443\r\n",
            b"Proxy-Connection: keep-alive\r\nUser-Agent: Safari-Split\r\n\r\n",
        ]
        accepted = mock.Mock()
        accepted.recv.return_value = b"HTTP/1.1 200 Connection Established\r\n\r\n"

        with mock.patch.object(core, "_normalize_host", return_value="chatgpt.com"), \
             mock.patch.object(core, "host_bypasses_proxy", return_value=False), \
             mock.patch.object(local_proxy_transport.socket, "socket", return_value=accepted), \
             mock.patch.object(engine, "_relay"):
            engine._handle_http(client)

        sent = b"".join(call.args[0] for call in accepted.sendall.call_args_list)
        self.assertIn(b"Proxy-Connection: keep-alive\r\n", sent)
        self.assertIn(b"User-Agent: Safari-Split\r\n", sent)
        self.assertEqual(client.recv.call_count, 2)

    def test_http_connect_forwards_bytes_buffered_after_headers(self):
        settings = {
            "upstream": [
                {"host": "proxy.test", "port": 8000, "username": "user", "password": "pass"},
            ]
        }
        engine = core.ProxyCore(settings)
        client = mock.Mock()
        early_tls = b"\x16\x03\x01\x00\x04test"
        client.recv.return_value = (
            b"CONNECT chatgpt.com:443 HTTP/1.1\r\n"
            b"Host: chatgpt.com:443\r\n\r\n"
            + early_tls
        )
        accepted = mock.Mock()
        accepted.recv.return_value = b"HTTP/1.1 200 Connection Established\r\n\r\n"

        with mock.patch.object(core, "_normalize_host", return_value="chatgpt.com"), \
             mock.patch.object(core, "host_bypasses_proxy", return_value=False), \
             mock.patch.object(local_proxy_transport.socket, "socket", return_value=accepted), \
             mock.patch.object(engine, "_relay"):
            engine._handle_http(client)

        sent_calls = [call.args[0] for call in accepted.sendall.call_args_list]
        self.assertGreaterEqual(len(sent_calls), 2)
        self.assertTrue(sent_calls[0].startswith(b"CONNECT chatgpt.com:443 HTTP/1.1\r\n"))
        self.assertEqual(sent_calls[-1], early_tls)

    def test_socks_connect_fails_over_after_rejected_upstream(self):
        settings = {
            "upstream": [
                {"host": "proxy-one.test", "port": 8000, "username": "one", "password": "bad"},
                {"host": "proxy-two.test", "port": 8001, "username": "two", "password": "good"},
            ]
        }
        engine = core.ProxyCore(settings)
        client = mock.Mock()
        client.recv.side_effect = [
            b"\x05",
            b"\x01",
            b"\x00",
            b"\x05\x01\x00\x03",
            b"\x0b",
            b"example.com",
            b"\x01\xbb",
        ]
        rejected = mock.Mock()
        rejected.recv.return_value = (
            b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n"
        )
        accepted = mock.Mock()
        accepted.recv.return_value = (
            b"HTTP/1.1 200 Connection Established\r\n\r\n"
        )

        with mock.patch.object(core, "_normalize_host", return_value="example.com"), \
             mock.patch.object(core, "host_bypasses_proxy", return_value=False), \
             mock.patch.object(local_proxy_transport.socket, "socket", side_effect=[rejected, accepted]), \
             mock.patch.object(engine, "_relay") as relay:
            engine._handle_socks(client)

        rejected.close.assert_called()
        accepted.connect.assert_called_once_with(("proxy-two.test", 8001))
        self.assertTrue(
            any(call.args[0].startswith(b"\x05\x00") for call in client.sendall.call_args_list)
        )
        relay.assert_called_once_with(accepted, client, engine._stop)


if __name__ == "__main__":
    unittest.main()