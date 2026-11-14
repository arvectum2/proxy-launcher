"""Scope guards for the independent standard WireGuard interoperability lab."""
from pathlib import Path

IOS = Path(__file__).resolve().parents[1] / "mobile/ios"
LAB = IOS / "Tools/WGReferenceLab"


def test_separate_official_pinned_runtime():
    build = (LAB / "build_peer.sh").read_text()
    assert "f333402bd9cbe0f3eeb02507bd14e23d7d639280" in build
    assert "go mod verify" in build and "-mod=readonly" in build
    assert "golang.zx2c4.com/wireguard" in build
    assert "xray|amnezia" in build and "CGO_ENABLED=0" in build
    assert "golang.zx2c4.com/wireguard" in (LAB / "go.mod").read_text()
    for path in (IOS / "project.yml", IOS / "ArvectumProxyLauncherIOS.xcodeproj/project.pbxproj"):
        assert "WGReferenceLab" not in path.read_text()


def test_single_loopback_udp_peer_and_single_synthetic_tcp_destination():
    src = (LAB / "main.go").read_text()
    assert "net.IPv4(127, 0, 0, 1)" in src
    assert "a.Port() != 39881" in src
    assert "e.Port() != 39881" in src
    assert 'netstack.CreateNetTUN' in src
    assert '"198.51.100.77:39883"' in src
    assert 'net.DialTimeout("tcp4", "127.0.0.1:39883"' in src
    assert "device.LogLevelSilent" in src
    assert "exec.Command" not in src


def test_distinct_reference_runner_and_receipt_oracle():
    runner = (IOS / "Tools/run_xray_vless_config_simulator_qa.sh").read_text()
    assert "--wg-reference" in runner
    assert "WGReferenceLab/build_peer.sh" in runner
    witness = (IOS / "Tools/run_xray_wireguard_peer_qa.py").read_text()
    assert "reference=False" in witness and "APL_WG_REFERENCE" in witness
    assert "seen!=[cases[0][1]]" in witness


def test_dual_lab_is_explicit_and_exact_destinations():
    config = (IOS / "Tools/XrayWireGuardLabConfig.swift").read_text()
    assert 'dual: Bool = false' in config
    assert '"2001:db8:77::77/128"' in config
    assert '"udp":dual' in config
    assert '"protocol":"wireguard"' in config
    assert '"freedom"' not in config
    source = (LAB / "main.go").read_text()
    assert 'if cfg.Dual' in source
    assert '"[2001:db8:77::77]:39883"' in source
    assert 'net.DialTimeout("udp4", "127.0.0.1:39883"' in source
    packet = (IOS / "Tools/XrayTunPacketQA.swift").read_text()
    assert "checksum(pseudo(udp.count,17,v6)+udp)" in packet
    assert "sendIP(fd,udp,17,v6)" in packet
    runner = (IOS / "Tools/run_xray_wireguard_peer_qa.py").read_text()
    assert 'received!=[int(expected)]*3' in runner
    assert 'TUN_QA_UDP_INJECTED_4' in runner and 'TUN_QA_UDP_INJECTED_6' in runner
