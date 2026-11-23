"""Fail-closed product-only VLESS activation while retaining import/backup."""
from pathlib import Path

IOS = Path(__file__).resolve().parents[1] / "mobile/ios"

def src(path):
    return (IOS / path).read_text()

def test_product_gate_is_release_only_and_keeps_two_physical_witnessed_transports():
    s = src("SharedCore/NativeCredentialRecord.swift")
    gate = s.split("enum NativeProductTransportGate {", 1)[1].split("/// Immutable versioned record", 1)[0]
    assert "case .wireGuard,.amneziaWG1:return true" in gate
    assert "case .vlessReality:" in gate
    assert "#if APL_NATIVE_PRODUCT_RUNTIME\n            return false" in gate
    assert "#else\n            return true" in gate
    candidate = s.split("func compileFullTunnelCandidate", 1)[1].split("struct Endpoint", 1)[0]
    assert "guard NativeProductTransportGate.allowsConnection(reference.kind)" in candidate
    assert "prepareVLESS(endpoint)" in candidate

def test_native_library_selection_is_ineligible_but_import_and_backup_survive():
    v = src("App/NativePersistentProfilesView.swift")
    assert "Button(tr(\"Select\",\"Выбрать\")){prepare(.select(row.reference))}.disabled(!row.canReview || !NativeProductTransportGate.allowsConnection(row.reference.kind))" in v
    assert "Text(status(.reviewOnly))" in v
    assert "Save reviewed profiles" in v and "previewAutomatic" in v
    session = src("SharedCore/NativePersistentProfileSession.swift")
    prepare = session.split("private func prepareAction", 1)[1].split("private func consume", 1)[0]
    confirm = session.split("func confirm(_ receipt", 1)[1]
    assert "guard NativeProductTransportGate.allowsConnection(ref.kind)" in prepare
    assert "guard NativeProductTransportGate.allowsConnection(ref.kind)" in confirm
    assert "case .remove(let ref)" in prepare and "case .replace(let ref)" in prepare

def test_launch_app_and_provider_guard_before_reading_credentials():
    store = src("Shared/ProfileStore.swift").split("func issueNativeProductLaunch", 1)[1].split("func revokeNativeProductLaunch", 1)[0]
    assert store.index("guard NativeProductTransportGate.allowsConnection(selection.reference.kind)") < store.index("let reader")
    app = src("App/VPNController.swift").split("private func connectProduct", 1)[1].split("private func connectWithLease", 1)[0]
    assert app.index("NativeProductTransportGate.allowsConnection") < app.index("let owner")
    provider = src("SharedCore/NativeCredentialReceiver.swift").split("struct NativeProductStartRequest", 1)[1].split("final class NativeProductProviderLane", 1)[0]
    assert provider.index("NativeProductTransportGate.allowsConnection(binding.reference.kind)") < provider.index("handoff.redeemProductStart")

def test_offline_vless_format_and_local_qa_are_still_available():
    record = src("SharedCore/NativeCredentialRecord.swift")
    assert "VLESSRealityShareLink.parse(source)" in record
    assert "XrayVLESSRuntimeConfig.compileValidatedCandidate" in record
    assert "NativeProfileBackupCodec" in src("SharedCore/NativeCredentialCatalog.swift")
    assert "VLESS Reality" in src("App/NativePersistentProfilesView.swift")
    assert "APL_NATIVE_PRODUCT_RUNTIME" in src("Tools/stage_ios_030_release_candidate.py")
