"""Source-only iCloud readiness gate; never claims actual Apple account, network or signing QA."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "mobile/ios/App"
IOS = ROOT / "mobile/ios"


def test_cloudkit_stays_disabled_without_provisioned_capability():
    project = (IOS / "project.yml").read_text()
    entitlements = (IOS / "Config/App.entitlements").read_text()
    assert "APL_CLOUDKIT_ENABLED" not in project
    assert "com.apple.developer.icloud" not in entitlements
    exclusions = (APP / "ExclusionsView.swift").read_text()
    assert "#if APL_CLOUDKIT_ENABLED" in exclusions
    assert "ExclusionCloudSyncView(model: model)" in exclusions


def test_cloudkit_upload_requires_explicit_preview_and_optimistic_lock():
    service = (APP / "ExclusionCloudKitService.swift").read_text()
    assert "privateCloudDatabase" in service
    assert ".ifServerRecordUnchanged" in service
    assert "requiresRemotePreview" in service
    assert "observedRemoteWasAbsent" in service
    assert "ExclusionSyncContract.encode(localDomains:" in service
    assert 'record["payload"] = data as NSData' in service


def test_cloudkit_user_consent_and_local_vpn_rollback():
    view = (APP / "ExclusionCloudSyncView.swift").read_text()
    exclusions = (APP / "ExclusionsView.swift").read_text()
    assert "confirmUpload = true" in view
    assert "confirmationDialog(" in view
    assert "await model.saveExclusions(" in view
    assert "currentRemote.manualDomains, graph: model.smartGraph)" in view
    assert "ExclusionSyncContract.remoteUnchanged(" in view
    assert "cloud.previewRemote()" in view
    assert "ExclusionSyncContract.localUnchanged(" in view
    assert "localAtPreview" in view
    assert "onApplied()" in view
    assert "entries != model.manualExclusions" in exclusions
    assert "graph != model.smartGraph.pruned()" in exclusions
    assert "onDismiss:" not in exclusions[exclusions.index("#if APL_CLOUDKIT_ENABLED\n            .sheet"):][:240]


def test_cloudkit_no_credentials_or_packet_tunnel_or_background_sync():
    service = (APP / "ExclusionCloudKitService.swift").read_text()
    combined = service + (APP / "ExclusionCloudSyncView.swift").read_text()
    assert "Keychain" not in service or "never" in service.lower()
    assert "SecItem" not in combined
    assert "UIApplication.shared" not in combined
    assert "PacketTunnelProvider" not in combined
    assert "CKContainer(identifier:" in service
    assert "manualDomains:" in combined
