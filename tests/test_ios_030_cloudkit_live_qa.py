"""Live QA is opt-in only and must never read or write the user's cloud record."""
from pathlib import Path

IOS = Path(__file__).resolve().parents[1] / "mobile/ios"

def source(path):
    return (IOS / path).read_text()

def test_private_qa_scope_and_release_barrier():
    service=source("App/ExclusionCloudKitService.swift")
    app=source("App/ArvectumProxyLauncherApp.swift")
    view=source("App/CloudKitLiveQAView.swift")
    assert 'recordName: "manual-exclusions.v1"' in service
    assert 'recordID = Self.recordID' in service
    assert 'recordName: "qa.manual-exclusions." + qaRunID.uuidString.lowercased()' in service
    assert service.count('guard syntheticDeviceID != nil, recordID != Self.recordID')==2
    assert 'database.record(for: recordID)' in service
    assert 'return syntheticDeviceID' in service
    assert 'CloudKitLiveQAView()' in app
    assert '#if APL_CLOUDKIT_LIVE_QA && APL_CLOUDKIT_ENABLED' in app
    assert '#if APL_CLOUDKIT_LIVE_QA && APL_CLOUDKIT_ENABLED' in view
    for forbidden in ('AppViewModel','ProfileStore','VPNController','UserDefaults','YandexAds','UIPasteboard'):
        assert forbidden not in view
    assert 'APL_CLOUDKIT_LIVE_QA' not in source('project.yml')
    assert "'APL_CLOUDKIT_LIVE_QA'" in source('Tools/stage_ios_030_release_candidate.py')

def test_exact_synthetic_conflict_and_cleanup_receipt():
    view=source("App/CloudKitLiveQAView.swift")
    service=source("App/ExclusionCloudKitService.swift")
    assert 'Set([command.runID,command.clientA,command.clientB]).count == 3' in view
    assert 'FileManager.default.removeItem(at: Self.input)' in view
    assert view.index('a.previewRemote(expectedAccount: account) == nil')<view.index('encode(command).write(to: Self.journal')<view.index('a.upload(manualDomains:')
    assert 'b.previewRemote(expectedAccount: account)' in view
    assert 'seen == first' in view and 'final == updated' in view
    assert 'catch ExclusionCloudKitFailure.requiresRemotePreview' in view
    assert 'tag != oldTag' in view
    assert 'expectedDevices.contains(snapshot.deviceID)' in service
    assert 'expectedDomains.contains(snapshot.manualDomains)' in service
    assert 'database.deleteRecord(withID: recordID)' in service
    assert 'previewRemote(expectedAccount: expectedAccount) == nil' in service
    assert view.index('try await a.qaDeleteSynthetic')<view.index('removeItem(at: Self.journal)')
    assert 'let physicalDevices = 1' in view
    assert 'let releaseAuthorized = false' in view
