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


def test_file_callbacks_use_captured_action_and_background_clears():
    view=(IOS/'App/NativeProfileReviewLabView.swift').read_text()
    assert '[receipt=importReceipt]' in view and '[receipt=exportReceipt]' in view
    assert 'lifecycle.consume(receipt)' in view
    assert 'kind:reviewedKind' in view and 'if value == .background {leave()}' in view
    assert 'lifecycle.leave();resetReview();session.clear()' in view
    assert 'receipt.id.uuidString.lowercased()' in view
    assert 'Discard cancelled file operation' in view


def test_qa_dedicated_ru_en_localization_keys_and_fallback():
    import re,json
    view=(IOS/'App/NativeProfileReviewLabView.swift').read_text()
    entry=(IOS/'App/ProfileBackupView.swift').read_text()
    ru=dict((json.loads(k),json.loads(v)) for k,v in re.findall(r'^\s*(".*?"):\s*(".*?"),$',view,re.M))
    assert len(ru)==21 and all(k!=v for k,v in ru.items())
    assert set(re.findall(r'tr\("([^"]+)"\)',view))|{'Native profiles · Simulator QA'}==set(ru)
    assert 'NativeReviewQAL10n.tr' in entry
    assert ru['Temporary profiles: %d'].count('%d')==1
    assert 'AppL10n.effectiveLanguage == "ru" else {return key}' in view
    assert not list((IOS/'Resources').glob('*.lproj/NativeReviewQA.strings'))
