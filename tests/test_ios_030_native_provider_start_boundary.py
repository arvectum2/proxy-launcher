from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/'mobile/ios'

def test_provider_dispatch_precedes_legacy_and_never_starts_native_runtime():
    src=(IOS/'PacketTunnel/PacketTunnelProvider.swift').read_text()
    start=src[src.index('override func startTunnel'):src.index('private func selectProxy')]
    boundary=start[:start.index('        stopping = false')]
    assert 'NativeProviderStartRequest.inspect' in boundary
    assert '#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION' in boundary
    assert 'let validationEnabled=false' in boundary
    assert 'request.validate(via:validationStore.makeNativeProviderValidationHandoff())' in boundary
    assert 'completionHandler(NSError(domain:"APLNativeStart",code:2))' in boundary
    assert 'completionHandler(nil)' not in boundary and 'setTunnelNetworkSettings' not in boundary
    assert 'if rejectedNativeWithoutLegacy && startTask==nil && active==nil' in start
    assert 'APL_NATIVE_PROVIDER_INTEGRATION' not in (IOS/'project.yml').read_text()
    app=(IOS/'App/VPNController.swift').read_text()
    assert 'for item in matching {try requireLegacyManager(item)}' in app
    assert 'try requireLegacyManager(manager)\n        let changed = reconcile(manager)' in app
