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


def test_dispatch_adapter_remains_inactive_and_has_deadline_and_lease():
    for directory in ("App", "PacketTunnel", "Shared"):
        for source in (IOS / directory).rglob("*.swift"):
            assert "TransportBackendAdapter" not in source.read_text()
    source = (IOS / "SharedCore/TransportBackendAdapter.swift").read_text()
    assert "@MainActor final class TransportBackendAdapter" in source
    assert "lease.acquire(owner)" in source
    assert "allOwnedProvidersQuiescent" in source
    assert "nativeReady && osConnected" in source
    assert "Task.sleep" in source and "timerID" in source
    assert "import NetworkExtension" not in source


def test_isolated_host_only_bounded_explicit_owned_manager():
    host = (IOS / "Tools/NativeTunnelLab/Host/NativeLabHost.swift").read_text()
    assert 'ru.arvectum.proxylauncher.lab.nativeqa.PacketTunnel' in host
    assert 'proto.providerConfiguration = ["labOwner": Self.marker]' in host
    assert 'named.allSatisfy(isOwned)' in host
    assert 'item.isOnDemandEnabled = false' in host
    assert 'let address=probeKind == "tcp6" ? "[2001:db8:77::77]" : "198.51.100.77"' in host
    assert 'URL(string:"http://"+address+":39883/"+value)' in host
    assert 'completionHandler(nil)' in host
    assert 'item.removeFromPreferences()' in host
    assert '.onAppear' not in host and '.onDemandRules' not in host
    assert 'NativeLabHost' not in (IOS / "project.yml").read_text()
