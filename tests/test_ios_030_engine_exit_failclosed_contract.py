from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "mobile/ios"


def test_native_exit_cancels_network_extension_without_direct_fallback():
    source = (ROOT / "PacketTunnel/PacketTunnelProvider.swift").read_text()
    assert "private let engineExitGate = TunnelEngineExitGate()" in source
    assert "let runGeneration = engineExitGate.begin()" in source
    assert "markUnexpectedExit(runGeneration)" in source
    assert "shouldCancelTunnel(runGeneration)" in source
    assert "self.cancelTunnelWithError(NSError(" in source
    assert "guard engineExitGate.isRunning(runGeneration) else" in source
    assert "if result != 0" not in source  # code zero still means no packet engine


def test_invalidate_before_native_stop_and_before_draining_for_failover():
    source = (ROOT / "PacketTunnel/PacketTunnelProvider.swift").read_text()
    stop = source.index("override func stopTunnel(")
    assert source.index("engineExitGate.invalidate()", stop) < source.index("tun2proxy_stop()", stop)
    rotate = source.index("private func switchTo(")
    assert source.index("engineExitGate.invalidate()", rotate) < source.index("TunnelEngineHandoff.stopAndDrain(", rotate)


def test_atomic_generation_drops_stale_queued_callbacks():
    source = (ROOT / "SharedCore/TunnelEngineExitGate.swift").read_text()
    assert "private let lock = NSLock()" in source
    assert "guard token == generation && state == .running" in source
    assert "return token == generation && state == .failed" in source
    assert "generation &+= 1" in source
