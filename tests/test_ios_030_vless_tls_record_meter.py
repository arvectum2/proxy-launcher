"""Isolated, content-free first TLS record witness for synthetic VLESS peer."""
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "mobile" / "ios" / "Tools"
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location("nativeqa_vless_tcp4_peer", TOOLS / "nativeqa_vless_tcp4_peer.py")
peer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(peer)


class FirstTLSRecordTests(unittest.TestCase):
    def test_no_content_is_incomplete(self):
        self.assertEqual(peer.TLSFirstRecordMeter().summary(), {"clientBytes": 0, "tlsHeader": "incomplete"})

    def test_fragmented_handshake_header_and_body(self):
        meter = peer.TLSFirstRecordMeter()
        meter.feed(b"\x16\x03")
        self.assertEqual(meter.summary()["tlsHeader"], "incomplete")
        meter.feed(b"\x01\x00\x07abc")
        self.assertEqual(meter.summary(), {"clientBytes": 8, "tlsHeader": "handshakeRecordHeader", "expectedFirstRecordBytes": 12, "firstRecordComplete": False})
        meter.feed(b"defg")
        self.assertTrue(meter.summary()["firstRecordComplete"])
        self.assertNotIn("abc", str(meter.summary()))

    def test_non_handshake_and_invalid_size_rejected(self):
        for prefix in (b"GET /", b"\x17\x03\x03\x00\x08", b"\x16\x03\x03\xff\xff", b"\x16\x03\x03\x00\x00"):
            meter=peer.TLSFirstRecordMeter()
            meter.feed(prefix)
            self.assertEqual(meter.summary()["tlsHeader"], "notHandshakeRecord")
            self.assertNotIn("expectedFirstRecordBytes", meter.summary())

    def test_multichunk_total_bytes_never_retains_payload(self):
        meter=peer.TLSFirstRecordMeter()
        meter.feed(b"\x16\x03\x01\x00\x01secret")
        meter.feed(b"more")
        data=meter.summary()
        self.assertEqual(data["clientBytes"], 15)
        self.assertTrue(data["firstRecordComplete"])
        self.assertNotIn("secret", str(data))
        self.assertEqual(len(meter._prefix), 5)


if __name__ == "__main__":
    unittest.main()
