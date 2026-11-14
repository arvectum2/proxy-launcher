"""Isolation and pinning guards, not a substitute for native runtime tests."""
from pathlib import Path

IOS = Path(__file__).resolve().parents[1] / "mobile/ios"
LAB = IOS / "Tools/AWGNativeLab"


def test_no_production_target_or_xray_link():
    for name in ("project.yml", "ArvectumProxyLauncherIOS.xcodeproj/project.pbxproj"):
        src = (IOS / name).read_text()
        assert "AWGNativeLab" not in src
        assert "aplAWGSelfTest" not in src
    runner = (LAB / "build_and_test.sh").read_text()
    assert "b5928efb6ca19f0153958460c3d141f04abc5c2e" in runner
    assert "544932844156d8172f7a28f77f2ac9c15a23046698b6243f633b0a0b00c0749c" in runner
    assert "go mod verify" in runner and "-mod=readonly" in runner
    assert "_CGoInvoke" in runner and "Unexpected Xray symbol" in runner
    assert "device install" not in runner and "allowProvisioningUpdates" not in runner


def test_loopback_and_synthetic_packet_only():
    src = (LAB / "main.go").read_text()
    assert 'net.IPv4(127, 0, 0, 1)' in src
    assert '192.0.2.1' in src and '2001:db8::1' in src
    assert 'netip.MustParseAddr("127.0.0.1")' in src
    assert 'rand.Read' in src and 'bytes.Equal(p, got)' in src
    assert 'CreateTUN' not in src and 'exec.Command' not in src
    assert 'device.LogLevelSilent' in src
    assert 'mode == 1' in src and 'mode == 2' in src


def test_locked_module_source():
    mod = (LAB / "go.mod").read_text()
    assert "github.com/amnezia-vpn/amneziawg-go/v3 v3.1.20260828" in mod
    assert "=> ../awg" in mod
    assert (LAB / "go.sum").stat().st_size > 1000
