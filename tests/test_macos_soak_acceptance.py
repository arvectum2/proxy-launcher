import importlib.util
import unittest
from pathlib import Path

source = Path(__file__).resolve().parents[1] / "mobile/macos-appstore/Tools/evaluate_socket_soak.py"
spec = importlib.util.spec_from_file_location("apl_soak_acceptance", source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def samples(tcp=36, wait=4):
    result = []
    for idx in range(66):
        result.append({
            "elapsed": min(idx * 60, 3900),
            "pid": 123,
            "vpn": "Connected",
            "tcp": tcp,
            "close_wait": wait,
            "arc_online": True,
            "https": {"rc": 0, "status": "200"} if idx % 5 == 0 else None,
        })
    return result


class SoakAcceptanceTests(unittest.TestCase):
    def test_healthy_sixty_five_minute_soak(self):
        self.assertEqual(module.assess(samples())["verdict"], "PASS")

    def test_socket_leak_must_fail_even_when_https_passes(self):
        data = samples()
        for idx, s in enumerate(data):
            s["tcp"] = 58 + int(idx / 65 * 250)
            s["close_wait"] = 18 + int(idx / 65 * 154)
        result = module.assess(data)
        self.assertEqual(result["verdict"], "FAIL")
        self.assertTrue(any("CLOSE_WAIT" in x for x in result["problems"]))

    def test_reject_short_test(self):
        data = samples()
        for idx, s in enumerate(data):
            s["elapsed"] = idx * 30
        self.assertEqual(module.assess(data)["verdict"], "FAIL")

    def test_reject_https_outage(self):
        data = samples()
        data[30]["https"] = {"rc": 28, "status": "000"}
        self.assertEqual(module.assess(data)["verdict"], "FAIL")

    def test_reject_arc_outage(self):
        data = samples()
        data[30]["arc_online"] = False
        self.assertEqual(module.assess(data)["verdict"], "FAIL")

    def test_reject_restart(self):
        data = samples()
        data[30]["pid"] = 456
        self.assertEqual(module.assess(data)["verdict"], "FAIL")

    def test_accept_short_lived_burst_that_drains(self):
        data = samples()
        data[4]["close_wait"] = 38
        data[4]["tcp"] = 90
        self.assertEqual(module.assess(data)["verdict"], "PASS")

    def test_reject_close_wait_rising_without_over_limit_peak(self):
        data = samples()
        for idx, s in enumerate(data):
            s["close_wait"] = 5 + int(idx / 65 * 22)
        self.assertEqual(module.assess(data)["verdict"], "FAIL")


if __name__ == "__main__":
    unittest.main()
