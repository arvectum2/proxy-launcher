"""Backoff behavior for multiple upstreams without disabling a sole upstream."""
import unittest
from unittest import mock

import local_proxy_transport
import proxy_core as core


class UpstreamFailoverTests(unittest.TestCase):
    def test_primary_enters_cooldown_after_two_failures(self):
        engine = core.ProxyCore({"upstream": [
            {"host": "primary.example", "port": 8000},
            {"host": "backup.example", "port": 8000},
        ]})
        first, second = engine._upstreams
        with mock.patch.object(local_proxy_transport.time, "monotonic", return_value=100.0):
            engine._record_upstream_result(first, False)
            self.assertEqual(engine._available_upstreams(), [first, second])
            engine._record_upstream_result(first, False)
            self.assertEqual(engine._available_upstreams(), [second])
        with mock.patch.object(local_proxy_transport.time, "monotonic", return_value=131.0):
            self.assertEqual(engine._available_upstreams(), [first, second])
            engine._record_upstream_result(first, True)
            self.assertNotIn(first, engine._upstream_cooldowns)

    def test_one_upstream_never_suppressed(self):
        engine = core.ProxyCore({"upstream": [{"host": "only.example", "port": 8000}]})
        only = engine._upstreams[0]
        for _ in range(6):
            engine._record_upstream_result(only, False)
        self.assertEqual(engine._available_upstreams(), [only])

    def test_all_failed_tries_earliest_recovery(self):
        engine = core.ProxyCore({"upstream": [
            {"host": "first.example", "port": 8000},
            {"host": "second.example", "port": 8000},
        ]})
        first, second = engine._upstreams
        with mock.patch.object(local_proxy_transport.time, "monotonic", return_value=100.0):
            engine._record_upstream_result(first, False)
            engine._record_upstream_result(first, False)
        with mock.patch.object(local_proxy_transport.time, "monotonic", return_value=110.0):
            engine._record_upstream_result(second, False)
            engine._record_upstream_result(second, False)
            self.assertEqual(engine._available_upstreams(), [first])


if __name__ == "__main__":
    unittest.main()
