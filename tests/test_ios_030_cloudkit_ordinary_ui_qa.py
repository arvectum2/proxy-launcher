from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/"mobile/ios"
def read(p):return (IOS/p).read_text()
def test_actual_screen_and_explicit_isolated_local_adapter():
    ui=read("App/ExclusionCloudSyncView.swift")
    qa=read("App/CloudKitOrdinaryUIQAView.swift")
    assert "extension AppViewModel: ExclusionCloudLocalModel {}" in ui
    assert "self.cloud = ExclusionCloudKitService()" in ui
    assert "#if APL_CLOUDKIT_LIVE_QA\n    init(model:" in ui
    assert "ExclusionCloudSyncView(model:local,qaCloud:client)" in qa
    assert "SyntheticCloudLocalModel: ExclusionCloudLocalModel" in qa
    for token in ("ProfileStore","VPNController","UserDefaults","AppViewModel"):
        assert token not in qa
    assert "a.upload(" not in qa
    assert "first.revision==1" in qa
    assert "updated.revision==2" in qa
    assert "local.applied==1" in qa
    assert "expectedDevices:[c.clientA.uuidString.lowercased(),c.clientB.uuidString.lowercased()]" in qa
    assert qa.index("encode(c).write(to:Self.journal")<qa.index("client=a")
    assert "APL_CLOUDKIT_LIVE_QA" not in read("project.yml")
