"""Offline-only handoff gate: no Xray activation until physical routing QA."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"


def test_xray_handoff_plan_cannot_mutate_live_packet_tunnel():
    src = (IOS / "SharedCore/XraySocksHandoffContract.swift").read_text()
    packet = (IOS / "PacketTunnel/PacketTunnelProvider.swift").read_text()
    assert "struct XraySocksHandoffPlan" in src
    assert "socks5://127.0.0.1:" in src
    assert "--dns virtual" in src
    assert "validBypassHost" in src
    assert "XraySocksHandoffPlan" not in packet
    for forbidden in ("CGoInvoke", "SecItem", "UserDefaults", "URLSession",
                      "print(", "NEPacketTunnelProvider", "--experimental-scoped-direct"):
        assert forbidden not in src


def test_lifecycle_requires_generation_and_failed_closed_gate():
    src = (IOS / "SharedCore/XraySocksHandoffContract.swift").read_text()
    assert "struct XrayHandoffLifecycle" in src
    assert "staleCallback" in src
    assert "failedClosed" in src
    assert "exhaustedGeneration" in src
    assert "generation += 1" in src
    assert "guard phase == .stopping" in src


def test_no_native_protocol_or_unsigned_pinned_binary_enabled():
    core = (IOS / "SharedCore/ProxyModel.swift").read_text()
    project = (IOS / "project.yml").read_text()
    assert "case vless" not in core.lower()
    assert "case wireguard" not in core.lower()
    assert "LibXray.xcframework" not in project
    assert "APL_XRAY_LAB" not in project
