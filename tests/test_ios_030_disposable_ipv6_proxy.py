"""Fail-closed one-shot IPv6 CONNECT lab proxy safety contracts."""
import importlib.util
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "mobile/ios/Tools/qa_disposable_ipv6_connect_proxy.py"
spec = importlib.util.spec_from_file_location("qa_disposable_ipv6_proxy", P)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_exact_allowlist_and_https_only():
    good = b"CONNECT v6.ident.me:443 HTTP/1.1\r\nHost: v6.ident.me:443\r\n\r\n"
    assert module.target_from_header(good) == "v6.ident.me"
    numeric = b"CONNECT [2606:4700:4700::1111]:443 HTTP/1.1\r\nHost: [2606:4700:4700::1111]\r\n\r\n"
    assert module.target_from_header(numeric) == "2606:4700:4700::1111"
    for bad in (
        b"GET http://v6.ident.me/ HTTP/1.1\r\n\r\n",
        b"CONNECT v6.ident.me:80 HTTP/1.1\r\n\r\n",
        b"CONNECT localhost:443 HTTP/1.1\r\n\r\n",
        b"CONNECT [::1]:443 HTTP/1.1\r\n\r\n",
        b"CONNECT [2001:db8::42]:443 HTTP/1.1\r\n\r\n",
        b"CONNECT [2606:4700:4700::1111]:22 HTTP/1.1\r\n\r\n",
        b"CONNECT 127.0.0.1:443 HTTP/1.1\r\n\r\n",
        b"CONNECT 192.168.1.80:443 HTTP/1.1\r\n\r\n",
        b"CONNECT secret.example:443 HTTP/1.1\r\n\r\n",
        b"CONNECT x.v6.ident.me:443 HTTP/1.1\r\n\r\n",
        b"CONNECT v6.ident.me:443 HTTP/2\r\n\r\n",
        b"CONNECT V6.IDENT.ME:443 HTTP/1.1\r\n\r\n",
        b"CONNECT v6.ident.me:443 HTTP/1.1\r\n\r\n" + b"a" * 5000,
    ):
        assert module.target_from_header(bad) is None


def test_bounded_lan_ipv6_only_and_no_sensitive_logging():
    s = P.read_text()
    assert 'LAB_BIND = ("127.0.0.1", "192.168.1.80")' in s
    assert "LAB_PORT = 18081" in s
    assert "MAX_CONCURRENCY = 12" in s
    assert "MAX_HEADER = 4096" in s
    assert 'family=socket.AF_INET6' in s
    assert "5 <= options.lifetime <= 180" in s
    for forbidden in (
        "print(host", "print(reader", "print(head", "print(payload",
        "print(data", "print(writer", "print(request", "print(client",
        "print(remote", "print(error", "print(addr",
        'shell=True', "0.0.0.0",
    ):
        assert forbidden not in s
