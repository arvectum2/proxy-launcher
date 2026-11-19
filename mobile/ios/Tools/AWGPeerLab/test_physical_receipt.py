import unittest
from unittest.mock import patch
from types import SimpleNamespace
from run_physical import assert_off, validate_receipt


class AWGPhysicalReceiptTests(unittest.TestCase):
    def test_valid_exact_positive_and_negative(self):
        for i, kind in enumerate(("tcp4", "tcp6", "udp4", "udp6")):
            counts = tuple(int(j == i) for j in range(4)) + (2, 3, 0)
            validate_receipt({"connected": True, "retainedOff": True, "receipt": True}, counts, kind, "positive")
        for mode in ("wrong-key", "wrong-psk"):
            validate_receipt({"connected": True, "retainedOff": True, "receipt": False}, (0, 0, 0, 0, 0, 1, 0), "udp4", mode)

    def test_reject_nonboolean_missing_transport_wrong_witness(self):
        item = {"connected": True, "retainedOff": True, "receipt": True}
        good = (1, 0, 0, 0, 2, 1, 0)
        for altered in (dict(item, retainedOff=1), dict(item, connected="true"), dict(item, receipt=False)):
            with self.assertRaises(RuntimeError):
                validate_receipt(altered, good, "tcp4", "positive")
        for counts in ((0, 1, 0, 0, 2, 1, 0), (1, 0, 0, 0, 0, 1, 0), (1, 0, 0, 0, 2, 0, 0)):
            with self.assertRaises(RuntimeError):
                validate_receipt(item, counts, "tcp4", "positive")
        with self.assertRaises(RuntimeError):
            validate_receipt(dict(item, receipt=False), good, "tcp4", "wrong-key")

    def test_refuse_any_visible_live_lab_or_production_extension(self):
        for name in ("Arvectum Packet Tunnel", "NativeLab.appex", "AWGProvider.appex"):
            with patch("run_physical.ctl", return_value=SimpleNamespace(stdout=name)):
                with self.assertRaises(RuntimeError):
                    assert_off()
        with patch("run_physical.ctl", return_value=SimpleNamespace(stdout="other process")):
            assert_off()


if __name__ == "__main__":
    unittest.main()
