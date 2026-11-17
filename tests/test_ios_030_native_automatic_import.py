from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/'mobile/ios'

def test_native_import_ui_explicit_controls_and_bounded_read():
    v=(IOS/'App/NativePersistentProfilesView.swift').read_text()
    assert 'allowsMultipleSelection:fileReceipt?.action == .automaticConfigurations' in v
    assert 'nativeImport.autoFiles' in v and 'nativeImport.clipboard' in v
    a=(IOS/'SharedCore/NativeAutomaticImport.swift').read_text()
    assert 'NativeAutomaticImport.readSources(urls)' in v and 'remaining-=source.utf8.count' in a
    assert 'read(upToCount:limit+1-data.count)' in a
    # Both reads must remain within the two explicit user-initiated previews.
    # No clipboard access in lifecycle, discovery, or automatic startup.
    replacement=v.split('private func previewReplacementClipboard(',1)[1].split('private func previewClipboard()',1)[0]
    automatic=v.split('private func previewClipboard()',1)[1].split('private func reviewBackup()',1)[0]
    assert v.count('UIPasteboard.general.string')==2
    for body in (replacement,automatic):
        assert body.count('UIPasteboard.general.string')==1
        assert body.index('guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil') < body.index('UIPasteboard.general.string')
    assert 'replacementTarget==target' in replacement
    assert 'session.previewReplacement(source,for:target)' in replacement
    assert 'Button(tr("Use clipboard","Вставить из буфера")){previewReplacementClipboard(target)}' in v
    assert 'Button(tr("Import from clipboard","Импорт из буфера")){previewClipboard()}' in v
    assert 'NativeCredentialRecord.create(profileID:ref.profileID,expected:ref.kind.transport,source:source)' in (IOS/'SharedCore/NativePersistentProfileSession.swift').read_text()
    assert 'private func previewClipboard()' in v and 'summary=try session.previewAutomatic([text])' in v
    assert 'session.confirmImport(summary,vpnInactive:inactive)' in v
    assert v.startswith('#if (DEBUG || APL_NATIVE_PRODUCT_RUNTIME) && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PERSISTENT_LIBRARY && !targetEnvironment(simulator)')
    assert 'startTunnel(' not in v and 'setTunnelNetworkSettings(' not in v

def test_auto_import_uses_existing_validation_and_single_restore_review():
    a=(IOS/'SharedCore/NativeAutomaticImport.swift').read_text()
    assert 'WGQuickConfigurationPreview.parse(source)' in a
    assert 'NativeCredentialRecord.create(' in a
    assert 'seen.insert(raw).inserted' in a
    r=(IOS/'SharedCore/NativeRestoreReview.swift').read_text()
    assert 'pending=nil\n        return try previewRecords(NativeAutomaticImport.prepare(sources))' in r
    assert 'catalog.restore(p.records,vpnInactive:vpnInactive)' in r
