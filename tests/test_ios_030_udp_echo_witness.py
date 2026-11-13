"""Safety checks for the bounded no-leak hardware UDP witness, without devices."""
import argparse
import importlib.util
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "mobile/ios/Tools/qa_udp_echo_witness.py"
spec = importlib.util.spec_from_file_location("qa_udp_echo_witness", SCRIPT)
assert spec is not None and spec.loader is not None
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


@pytest.mark.parametrize("invalid", [
    "127.0.0.1", "::1", "::", "fe80::1234", "fd00::2",
    "2001:db8::1", "::ffff:192.168.1.1", "garbage",
])
def test_rejects_all_non_global_or_non_ipv6_bind(invalid):
    with pytest.raises(argparse.ArgumentTypeError):
        mod.valid_bind(invalid)


def test_public_ipv6_bind_permitted():
    assert mod.valid_bind("2606:4700:4700::1111") == "2606:4700:4700::1111"


def test_token_is_exact_and_bounded_no_amplification():
    token = b"APL030-" + b"a" * 32
    assert len(token) == 39 and mod.accepted(token)
    for bad in [b"", token + b"x", token[:-1], b"APL020-" + b"a" * 32,
                b"APL030-" + b"G" * 32, b"APL030-" + b"a" * 1000]:
        assert not mod.accepted(bad)


def test_no_sensitive_udp_payload_or_client_logged():
    source = SCRIPT.read_text()
    assert "print(packet" not in source
    assert "print(peer" not in source
    assert "print(bind" not in source
    assert "server.sendto(packet, peer)" in source
    assert "server.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)" in source
    assert "deadline = time.monotonic() + lifetime" in source
