"""Fail-closed, aggregate-only Smart4 dry-run source contract."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / "mobile/ios/SharedCore/SmartRouteDryRunAudit.swift").read_text()
PACKET = (ROOT / "mobile/ios/PacketTunnel/PacketTunnelProvider.swift").read_text()
APP_VM = (ROOT / "mobile/ios/App/AppViewModel.swift").read_text()
UI = (ROOT / "mobile/ios/App/ExclusionsView.swift").read_text()

class Smart4DryRunContract(unittest.TestCase):
    def test_never_changes_existing_runtime_route(self):
        for runtime in (PACKET, APP_VM, UI):
            self.assertNotIn("Smart4DryRunAudit", runtime)
        for forbidden in ("NetworkExtension", "NEPacketTunnel",
                          "setTunnelNetworkSettings", "excludedRoutes",
                          "includedRoutes", "NWConnection(", "URLSession("):
            self.assertNotIn(forbidden, CORE)

    def test_no_private_fields_or_telemetry_sink(self):
        for forbidden in ("UserDefaults", "TelemetryStore", "TunnelEvent",
                          "FileManager", "JSONEncoder", "print(", "Logger(",
                          "SecItem", "Keychain", "NWPathMonitor"):
            self.assertNotIn(forbidden, CORE)
        match = re.search(r"struct Smart4DryRunSummary: Equatable \{(.*?)\n\}", CORE, re.S)
        self.assertIsNotNone(match)
        fields = re.findall(r"^\s*let\s+(\w+):\s*(\w+)", match.group(1), re.M)
        self.assertEqual(dict(fields), {
            "enabled":"Bool", "observed":"Int", "confirmedMatches":"Int",
            "confirmedMismatches":"Int", "inconclusive":"Int",
            "proposedDirect":"Int", "proposedProxy":"Int", "capped":"Bool"})
        self.assertNotRegex(match.group(1), r"host|ip|url|password|username")

    def test_default_off_bounded_and_unknown_cannot_confirm(self):
        for expected in ("private var optedIn = false",
                         "guard optedIn else { return }",
                         "guard observed < Self.maximumSamples",
                         "case .unknown, .inferredOnlyFromIP:",
                         "inconclusive += 1",
                         "self = Smart4DryRunAudit(optedIn: value)",
                         "policy.explain(host: host, resolvedIP: resolvedIP)"):
            self.assertIn(expected, CORE)

if __name__ == "__main__":
    unittest.main()
