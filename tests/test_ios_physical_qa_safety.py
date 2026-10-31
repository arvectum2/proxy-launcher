"""Guard against accidentally shipping/triggering ephemeral real-VPN QA."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / 'mobile/ios/App/AppViewModel.swift').read_text(encoding="utf-8")
MANAGER = (ROOT / 'mobile/ios/App/VPNController.swift').read_text(encoding="utf-8")
TUNNEL = (ROOT / 'mobile/ios/PacketTunnel/PacketTunnelProvider.swift').read_text(encoding="utf-8")
RUNNER = (ROOT / 'mobile/ios/Tests/UITests/PhysicalVPNControlledUITests.swift').read_text(encoding="utf-8")

class PhysicalQASafety(unittest.TestCase):
    def test_tunnel_requires_explicit_debug_launch_arg(self):
        for code in (APP, MANAGER, TUNNEL):
            self.assertIn('#if DEBUG', code)
        self.assertIn('ProcessInfo.processInfo.arguments.contains("-aplEphemeralTunnelQA")', APP)
        self.assertIn('ProcessInfo.processInfo.arguments.contains("-aplEphemeralTunnelQA")', MANAGER)
        self.assertIn('qaStopAfterSeconds', MANAGER)
        self.assertIn('qaStopAfterSeconds', TUNNEL)
        self.assertIn('cancelTunnelWithError', TUNNEL)
        self.assertIn('self?.vpn.disconnect()', APP)

    def test_hardware_tunnel_test_is_opt_in(self):
        self.assertIn('#if APL_RUN_EXPLICIT_VPN_QA', RUNNER)
        self.assertIn('app.staticTexts["Отключено"]', RUNNER)
        self.assertIn('app.buttons["Отключить"]', RUNNER)
        self.assertIn('XCTSkip(', RUNNER)
        self.assertNotIn('saveProfile(', RUNNER)
        self.assertNotIn('password(for:', RUNNER)

    def test_public_egress_proof_is_strictly_opt_in_and_private(self):
        source = (ROOT / 'mobile/ios/Tests/UITests/PhysicalProxyEgressUITests.swift').read_text(encoding='utf-8')
        self.assertIn('#if APL_RUN_EXPLICIT_VPN_QA', source)
        self.assertIn('#if targetEnvironment(simulator)', source)
        self.assertIn('"-aplEphemeralTunnelQA"', source)
        self.assertIn('app.staticTexts["Отключено"]', source)
        self.assertIn('app.buttons["Отключить"]', source)
        self.assertIn('throw XCTSkip(', source)
        self.assertIn('https://api.ipify.org', source)
        self.assertIn('https://www.cloudflare.com/cdn-cgi/trace', source)
        self.assertIn('raw_addresses=redacted', source)
        self.assertIn('baseline_stable=true', source)
        self.assertIn('for attempt in 1...4', source)
        self.assertNotIn('print(before', source)
        self.assertNotIn('print(during', source)
        self.assertNotIn('print(after', source)
        self.assertNotIn('saveProfile(', source)
        self.assertNotIn('password(for:', source)

if __name__ == '__main__':
    unittest.main()
