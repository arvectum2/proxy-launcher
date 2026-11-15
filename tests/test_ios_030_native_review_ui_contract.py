from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/'mobile/ios'


def test_simulator_only_preview_and_no_production_flag():
    view=(IOS/'App/NativeProfileReviewLabView.swift').read_text()
    gate='#if DEBUG && APL_NATIVE_PROFILE_REVIEW && targetEnvironment(simulator)'
    assert view.startswith(gate)
    assert gate in (IOS/'App/ProfileBackupView.swift').read_text()
    assert 'APL_NATIVE_PROFILE_REVIEW' not in (IOS/'project.yml').read_text()
    for forbidden in ('VPNController','ProfileStore','NativeCredentialKeychain','NETunnelProvider','CloudKit','UIPasteboard','UserDefaults'):
        assert forbidden not in view
    assert 'session.clear()' in view and 'session.cancelReview()' in view
    assert 'SecureField' in view and 'FileWrapper(regularFileWithContents:bytes)' in view


def test_rehearsal_is_memory_only_and_has_no_connection_api():
    core=(IOS/'SharedCore/NativeProfileReviewSession.swift').read_text()
    assert 'MemoryCatalog' in core and 'MemoryItems' in core
    assert 'review.confirm(summary,vpnInactive:{true})' in core
    assert 'Never reuse' in core
    for forbidden in ('NativeCredentialKeychain','ProfileStore','NetworkExtension','startTunnel','SecItem','UserDefaults'):
        assert forbidden not in core
