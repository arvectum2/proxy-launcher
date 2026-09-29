import socket
import struct
import unittest
from unittest import mock

import windows_redirect_transport as redirect


def sockaddr_v4(host, port):
    raw = bytearray(redirect.SOCKADDR_STORAGE_SIZE)
    raw[0:2] = int(socket.AF_INET).to_bytes(2, "little")
    raw[2:4] = int(port).to_bytes(2, "big")
    raw[4:8] = socket.inet_pton(socket.AF_INET, host)
    return bytes(raw)


def sockaddr_v6(host, port):
    raw = bytearray(redirect.SOCKADDR_STORAGE_SIZE)
    raw[0:2] = int(socket.AF_INET6).to_bytes(2, "little")
    raw[2:4] = int(port).to_bytes(2, "big")
    raw[8:24] = socket.inet_pton(socket.AF_INET6, host)
    return bytes(raw)


def context(remote, local):
    return (
        struct.pack("<II", redirect.CONTEXT_MAGIC, redirect.CONTEXT_VERSION)
        + remote
        + local
    )


class WindowsRedirectTransportTests(unittest.TestCase):
    def test_parse_ipv4_context(self):
        remote, local = redirect.parse_redirect_context(
            context(
                sockaddr_v4("203.0.113.9", 443),
                sockaddr_v4("192.0.2.10", 50123),
            )
        )
        self.assertEqual(remote, ("203.0.113.9", 443))
        self.assertEqual(local, ("192.0.2.10", 50123))
    def test_parse_ipv6_context(self):
        remote, local = redirect.parse_redirect_context(
            context(
                sockaddr_v6("2001:db8::7", 8443),
                sockaddr_v6("2001:db8::10", 51000),
            )
        )
        self.assertEqual(remote, ("2001:db8::7", 8443))
        self.assertEqual(local, ("2001:db8::10", 51000))

    def test_wrong_owner_or_version_fails_closed(self):
        payload = (
            struct.pack("<II", 0x11111111, redirect.CONTEXT_VERSION)
            + sockaddr_v4("203.0.113.9", 443)
            + sockaddr_v4("192.0.2.10", 50123)
        )
        with self.assertRaises(redirect.WindowsRedirectTransportError):
            redirect.parse_redirect_context(payload)

    def test_query_requires_records_and_context(self):
        payload = context(
            sockaddr_v4("203.0.113.9", 443),
            sockaddr_v4("192.0.2.10", 50123),
        )
        calls = []

        def ioctl(sock, code, **kwargs):
            calls.append((code, kwargs))
            if code == redirect.SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS:
                return b"records"
            return payload

        metadata = redirect.query_redirect_metadata(object(), ioctl=ioctl)
        self.assertEqual(metadata.original_remote, ("203.0.113.9", 443))
        self.assertEqual(metadata.redirect_records, b"records")
        self.assertEqual(
            [item[0] for item in calls],
            [
                redirect.SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS,
                redirect.SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT,
            ],
        )
    def test_attach_redirect_records_uses_set_ioctl(self):
        calls = []

        def ioctl(sock, code, **kwargs):
            calls.append((sock, code, kwargs))
            return b""

        outbound = object()
        redirect.attach_redirect_records(outbound, b"chain", ioctl=ioctl)
        self.assertEqual(calls[0][0], outbound)
        self.assertEqual(
            calls[0][1], redirect.SIO_SET_WFP_CONNECTION_REDIRECT_RECORDS
        )
        self.assertEqual(calls[0][2]["input_bytes"], b"chain")

    def test_non_windows_real_ioctl_fails_closed(self):
        with mock.patch.object(redirect.sys, "platform", "linux"):
            with self.assertRaises(redirect.WindowsRedirectTransportError):
                redirect._winsock_ioctl(
                    mock.Mock(),
                    redirect.SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT,
                    output_size=redirect.REDIRECT_CONTEXT_SIZE,
                )


if __name__ == "__main__":
    unittest.main()
