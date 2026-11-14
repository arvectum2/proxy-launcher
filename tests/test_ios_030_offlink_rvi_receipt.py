"""Synthetic cases only: the real RVI receipt must come from a device."""
import contextlib
import importlib.util
import io
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "offlink", ROOT / "mobile/ios/Tools/qa_offlink_rvi_receipt.py")
OFFLINK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OFFLINK)


class OffLinkRVIGuards(unittest.TestCase):
    marks = """APL_OFFLINK_WINDOW_BEFORE_BEGIN_100.0
APL_OFFLINK_WINDOW_BEFORE_END_104.0
APL_OFFLINK_DISPOSABLE_EGRESS_CONFIRMED
APL_OFFLINK_WINDOW_DURING_BEGIN_110.0
APL_OFFLINK_WINDOW_DURING_END_114.0
APL_OFFLINK_VPN_OFF_CONFIRMED
APL_OFFLINK_WINDOW_AFTER_BEGIN_120.0
APL_OFFLINK_WINDOW_AFTER_END_124.0
** TEST EXECUTE SUCCEEDED **"""
    # Public source strings are illustrative, not captured owner addresses.
    def packet(self, timestamp, port, src="2606:4700:4700::1001"):
        return f"{timestamp} IP6 {src}.49152 > 2606:4700:4700::1111.{port}: UDP, length 40"

    def baseline(self):
        return "\n".join(self.packet(t, p) for t in (101, 121) for p in (53, 443))

    def evaluate(self, log, packets, stats="0 packets dropped by kernel"):
        with contextlib.redirect_stdout(io.StringIO()):
            return OFFLINK.evaluate(log, packets, stats)

    def test_accepts_positive_controls_and_no_global_underlay_packet(self):
        capture = self.baseline() + "\n" + self.packet(111, 443, "2001:db8::1")
        self.assertEqual(self.evaluate(self.marks, capture),
                         "BOUNDED_OFFLINK_PHYSICAL_UDP_NOT_OBSERVED")

    def test_global_packet_detected_even_if_xctest_failed(self):
        capture = self.baseline() + "\n" + self.packet(111, 53)
        self.assertEqual(self.evaluate(self.marks.replace("SUCCEEDED", "FAILED"), capture),
                         "OFFLINK_PHYSICAL_UDP_OBSERVED")

    def test_missing_after_control_is_inconclusive(self):
        capture = "\n".join(self.packet(101, p) for p in (53, 443))
        self.assertEqual(self.evaluate(self.marks, capture), "INCONCLUSIVE")

    def test_capture_drops_are_inconclusive(self):
        self.assertEqual(self.evaluate(self.marks, self.baseline(), "1 packets dropped by kernel"),
                         "INCONCLUSIVE")

    def test_duplicate_phase_rejected(self):
        with self.assertRaises(ValueError):
            self.evaluate(self.marks + "\nAPL_OFFLINK_WINDOW_BEFORE_BEGIN_100.0", self.baseline())


if __name__ == "__main__":
    unittest.main()
