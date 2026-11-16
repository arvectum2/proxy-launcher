"""Dependency-free unittest gates: Windows P0 runs standard unittest discovery."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mobile/ios/PacketTunnel/PacketTunnelProvider.swift"
GATE = ROOT / "mobile/ios/SharedCore/TunnelQACallbackGate.swift"
TESTS = ROOT / "mobile/ios/Tests/CoreTests/TunnelQACallbackGateTests.swift"


class QATimerGenerationContracts(unittest.TestCase):
    def test_start_and_stop_invalidate_stale_callbacks(self):
        source = SOURCE.read_text()
        self.assertIn("private let qaCallbackGate = TunnelQACallbackGate()", source)
        self.assertIn("let qaSession = qaCallbackGate.begin()", source)
        self.assertIn("qaCallbackGate.invalidate()", source)
        self.assertEqual(source.count("qaCallbackGate.performIfCurrent(qaSession)"), 2)

    def test_both_timers_fail_closed_on_old_sessions(self):
        source = SOURCE.read_text()
        reset = source.split('options?["qaResetDirectAfterSeconds"]', 1)[1].split(
            "forceNetworkChangeForQA()", 1)[0]
        timeout = source.split("DispatchQueue.main.asyncAfter(deadline: .now() + value.doubleValue)", 1)[1].split(
            "cancelTunnelWithError", 1)[0]
        self.assertIn("performIfCurrent(qaSession)", reset)
        self.assertIn("performIfCurrent(qaSession)", timeout)
        self.assertIn("guard !self.stopping", reset)
        self.assertIn("guard !self.stopping", timeout)

    def test_guard_serializes_check_with_actual_callback(self):
        source = GATE.read_text()
        self.assertIn("private let lock = NSRecursiveLock()", source)
        snippet = source.split("func performIfCurrent", 1)[1]
        self.assertLess(snippet.index("lock.lock()"), snippet.index("guard active && token == generation"))
        self.assertLess(snippet.index("guard active && token == generation"), snippet.index("action()"))
        for method in ("begin()", "invalidate()", "isCurrent(", "performIfCurrent("):
            self.assertIn(method, source)

    def test_reconnect_and_concurrency_have_deterministic_swift_tests(self):
        source = TESTS.read_text()
        for test in (
            "testOnlyCurrentSessionMayAct",
            "testExplicitStopSuppressesOldTimeoutAndReset",
            "testReconnectCannotBeStoppedByPreviousSessionTimer",
            "testRepeatedStartWithoutStopStillInvalidatesOldGeneration",
            "testSynchronousStopInsideCallbackIsSafe",
            "testConcurrentStaleCallbacksStayBlockedAfterReconnect",
        ):
            self.assertIn(test, source)


if __name__ == "__main__":
    unittest.main()
