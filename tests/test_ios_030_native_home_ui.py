from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/"mobile/ios"

def test_native_selection_reaches_same_home_toggle_as_legacy():
    home=(IOS/"App/ContentView.swift").read_text()
    model=(IOS/"App/AppViewModel.swift").read_text()
    assert "HomeConnectionProfilePolicy.offersAdd(" in model
    assert "nativeSelectionPresent:nativeSelectionPresent" in model
    assert "model.offersAddFromHome(preview:qaProfile)" in home
    for region in (home.split("private var homeConnectControl:",1)[1].split("private var homeProfileControl:",1)[0],
                   home.split("private var primaryActionTitle:",1)[1].split("private var connectionStatusColor:",1)[0]):
        assert "if offersAddFromHome" in region
        assert "model.profiles.isEmpty" not in region
    assert "label:homeProfileLabel(!hasHomeTarget ?" in home
    assert "(!model.nativeSelectionPresent && model.automaticSelection)" in home
    selection=model.split("var nativeSelectionPresent:Bool",1)[1].split("var selectedLabel:",1)[0]
    assert "catch {return true}" in selection
    toggle=model.split("func toggleVPN() async",1)[1]
    assert toggle.index("try store.nativeProductSelection() != nil")<toggle.index("guard !profiles.isEmpty")
    assert "try await vpn.connect();return" in toggle
    assert "return false" in (IOS/"SharedCore/NativeCredentialRecord.swift").read_text().split("enum NativeProductTransportGate",1)[1].split("struct NativeCredentialRecord",1)[0]
