from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/'mobile/ios'


def test_real_native_library_device_gate_and_explicit_mutations():
    gate='#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PERSISTENT_LIBRARY && !targetEnvironment(simulator)'
    view=(IOS/'App/NativePersistentProfilesView.swift').read_text()
    assert view.startswith(gate+'\n')
    assert 'session=model.makePersistentNativeLibrary()' in view
    assert 'model.vpn.withNativeLibraryWrite' in view and 'session.confirmImport' in view
    assert 'generation==token,lifecycle.visible' in view and 'lifecycle.consume(token)' in view
    assert 'session?.cancel()' in view and 'session=nil' in view
    assert 'Review removal' in view and 'Review retired revisions' in view
    assert 'startVPNTunnel' not in view and 'connect()' not in view and 'SecItem' not in view
    profiles=(IOS/'App/ProfilesScreenView.swift').read_text()
    assert gate in profiles and 'profiles.nativeStorageQA' in profiles
    assert 'APL_NATIVE_PERSISTENT_LIBRARY' not in (IOS/'project.yml').read_text()
    model=(IOS/'App/AppViewModel.swift').read_text()
    assert gate in model and 'store.makeNativeCredentialCatalog()' in model
    controller=(IOS/'App/VPNController.swift').read_text();start=controller.index('func withNativeLibraryWrite');end=controller.index('#endif',start);body=controller[start:end]
    assert 'operationGate.perform(.restore)' in body and 'loadAllManagers(requireResult:true)' in body
    assert 'onDemandRules' in body and 'status == .disconnected' in body
    assert 'saveToPreferences' not in body and 'loadOrCreateManager' not in body


def test_native_policy_uses_same_classifier_provider_and_ui_without_direct_route_changes():
    store=(IOS/'Shared/ProfileStore.swift').read_text()
    assert 'NativeRoutingAdmission.inspect(manual:defaults.object' in store
    assert 'nativeValidationPolicyIsEmpty() throws -> Bool {nativeRoutingAdmission().permitsSelection}' in store
    assert 'guard let bytes = raw as? Data else {throw ProfileStoreError.corruptProfiles}' in store
    provider=(IOS/'PacketTunnel/PacketTunnelProvider.swift').read_text()
    assert 'validationStore.nativeValidationPolicyIsEmpty()' in provider
    core=(IOS/'SharedCore/NativePersistentProfileSession.swift').read_text()
    assert 'self.policy().permitsSelection' in core and 'vpnInactive:vpnInactive' in core
    assert 'NativeCredentialHandoff' not in core and 'startTunnel' not in core


def test_persistent_backup_uses_same_review_and_ciphertext_only_file_export():
    view=(IOS/'App/NativePersistentProfilesView.swift').read_text()
    assert 'choose(.backup)' in view and 'ProfileBackupCodec.readEncryptedFile(at:url)' in view
    assert 'session.previewBackup(bytes,password:secret)' in view
    assert 'session.confirmExport(receipt,password:secret,vpnInactive:inactive)' in view
    assert 'lifecycle.begin(.export)' in view and 'lifecycle.consume(token) == .export' in view
    assert 'password="";repeatedPassword=""' in view and 'document=nil' in view
    assert 'phase == .active' in view and 'generation==token' in view
    core=(IOS/'SharedCore/NativeCredentialCatalog.swift').read_text()
    assert 'var mutationEpoch: UUID? = nil' in core
    assert 'var next=s;next.mutationEpoch=UUID()' in core
    assert 'try reader.storage.replace(bytes)\n        s=next' in core
    assert 'NativeProfileBackupCodec.seal(records,password:password)' in core
    assert 'try publish(&journal)' in core
