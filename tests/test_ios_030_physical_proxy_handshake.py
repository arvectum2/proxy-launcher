"""Guard that physical proxy handshake QA cannot mutate VPN or log secrets."""
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "mobile/ios/Tests/DeviceKeychainTests/PhysicalProxyHandshakeReadOnlyTests.swift"


def test_hardware_proxy_qa_read_only_and_ci_skip():
    text = SRC.read_text()
    assert 'targetEnvironment(simulator)' in text and 'throw XCTSkip(' in text
    assert 'try await probe.resolveMeasured(profile, password: password)' in text
    assert 'try store.password(for: profile.id)' in text
    for forbidden in (
        'store.save(', 'store.delete(', 'setPassword(', 'SecItemAdd', 'SecItemDelete',
        'startTunnel(', 'connectVPN(', 'NETunnelProviderManager', 'app.launch(',
        'profile.host', 'profile.username', 'print(password', 'print(error',
        'String(describing: error)', 'XCTAssertEqual(password',
    ):
        assert forbidden not in text


def test_probe_uses_existing_production_implementation():
    text = SRC.read_text()
    assert 'let probe = ProxyProbe()' in text
    assert 'APL_PROXY_QA_CONNECT_PASSED_' in text
    assert 'XCTAssertGreaterThan(succeeded, 0' in text
