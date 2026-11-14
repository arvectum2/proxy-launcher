"""New backend planning remains isolated from production activation."""
from pathlib import Path

IOS = Path(__file__).resolve().parents[1] / "mobile/ios"


def test_no_production_backend_activation_or_storage_change():
    for directory in ("App", "PacketTunnel", "Shared"):
        for source in (IOS / directory).rglob("*.swift"):
            text = source.read_text()
            assert "TransportBackendCoordinator" not in text
            assert "TransportBackendPlan" not in text
    assert "case vlessReality" not in (IOS / "SharedCore/ProxyModel.swift").read_text()
    project = (IOS / "project.yml").read_text()
    assert "LibXray.xcframework" not in project
    assert "AWGNativeLab" not in project
    assert "WGReferenceLab" not in project


def test_planning_contract_is_pure_and_requires_two_receipts():
    source = (IOS / "SharedCore/TransportBackendContract.swift").read_text()
    assert "scope == .syntheticLab" in source
    assert "routes == .tunnelOnly" in source
    assert "required.isSubset(of: evidence)" in source
    assert "nativeDrained && osDisconnected" in source
    assert "private let epoch = UUID()" in source
    assert "return try failClosed(token)" in source
    assert "import NetworkExtension" not in source
    assert "import LibXray" not in source
    assert "import tun2proxy" not in source
