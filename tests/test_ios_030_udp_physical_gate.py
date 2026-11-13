"""Device QA safety contracts using unittest, with no hardware execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "mobile/ios/Tests/DeviceKeychainTests/PhysicalDisposableIPv6UpstreamTests.swift"


class PhysicalUDPLeakGateTests(unittest.TestCase):
    def test_requires_opt_in_public_ipv6_before_starting_vpn(self):
        text = PROBE.read_text()
        method = text.split("func testBoundedUDPDirectWitnessBlockedInPacketTunnelAndRestored()", 1)[1]
        self.assertIn('#if targetEnvironment(simulator)', method)
        self.assertIn('env["APL_QA_UDP_ENABLE"] == "YES"', method)
        self.assertIn('env["APL_QA_UDP_WITNESS_IPV6"]', method)
        self.assertIn('env["APL_QA_UDP_WITNESS_PORT"]', method)
        self.assertIn('portNumber >= 1024', method)
        self.assertIn('inet_pton(AF_INET6', method)
        self.assertIn('bytes[0] & 0xe0', method)
        self.assertLess(method.index('env["APL_QA_UDP_ENABLE"]'),
                        method.index('existingOffTunnel()'))
        self.assertLess(method.index('existingOffTunnel()'),
                        method.index('tunnel.startTunnel(options:'))

    def test_no_owner_proxy_changes_and_bounded_stop(self):
        text = PROBE.read_text()
        method = text.split("func testBoundedUDPDirectWitnessBlockedInPacketTunnelAndRestored()", 1)[1]
        for expected in (
            'await udpEcho(witness, port: port)', 'labProxy.allowFailover = false',
            'ipv6Witness(labProxy)', '(try? await ipv6Witness(nil)) == labOrigin',
            '"qaSmart3ProxyHost": "192.168.1.80"',
            '"qaSmart3ProxyPort": NSNumber(value: 18081)',
            '"qaStopAfterSeconds": NSNumber(value: 25)',
            'deadline: .now() + 20', 'tunnel.stopVPNTunnel()',
            'XCTAssertFalse(escaped', 'XCTAssertTrue(restored'
        ):
            self.assertIn(expected, method)
        for unsafe in (
            "saveToPreferences", "removeFromPreferences", "SecItemDelete",
            "SecItemAdd", "store.save(", "print(host", "print(token",
            "print(witness", "print(labOrigin", "print(profile", "print(password"
        ):
            self.assertNotIn(unsafe, method)

    def test_single_nonce_echo_is_bounded_and_exact(self):
        text = PROBE.read_text()
        snippet = text.split("private func udpEcho(", 1)[1].split(
            "func testBoundedUDPDirectWitnessBlockedInPacketTunnelAndRestored()", 1)[0]
        for expected in (
            '"APL030-" + UUID().uuidString', 'connection.send(content: token',
            'response == token', 'deadline: .now() + 2.5',
            'Once()', 'connection.cancel()'
        ):
            self.assertIn(expected, snippet)


if __name__ == "__main__":
    unittest.main()
