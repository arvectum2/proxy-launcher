from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/'mobile/ios'


def test_concrete_xray_abi_only_under_explicit_candidate_gate():
    driver=(IOS/'PacketTunnel/NativeXrayRuntimeDriver.swift').read_text()
    assert driver.startswith('#if (DEBUG || APL_NATIVE_RELEASE_LINK_PREPARATION || APL_NATIVE_PRODUCT_RUNTIME) && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_XRAY_CANDIDATE\n')
    assert 'CGoInvoke(input)' in driver and 'defer{CGoFree(reply)}' in driver
    assert 'CFBooleanGetTypeID()' in driver and 'maxResponseBytes' in driver
    assert 'static let shared=NativeXrayRuntimeDriver()' in driver
    assert 'runtimeOwner=owner' in driver and 'guard runtimeOwner==owner' in driver
    assert 'TunnelEngineHandoff.stopAndDrain' in driver
    provider=(IOS/'PacketTunnel/PacketTunnelProvider.swift').read_text()
    assert 'inspectConfiguration:driver.validate' in provider
    assert 'guard request.expected.reference.kind.provider == .rustXray' in provider
    assert 'startXray(' not in provider and 'drainOwnedRustRunner(' not in provider
    assert 'APL_NATIVE_XRAY_CANDIDATE' not in (IOS/'project.yml').read_text()


def test_source_candidate_compile_lane_restricts_artifacts_and_exports_only_receipt():
    script=(IOS/'Tools/build_product_xray_candidate_unsigned.sh').read_text()
    assert '[[ $# == 4 ]]' in script
    assert 'verify_xray_source_candidate.py' in script and 'verify_tun2proxy_lab_artifact.py' in script
    assert 'e81642cf494e218aeb3314289f235eeff8dff21dc8d72b8bd23ded8b41c0b852' in script
    assert 'CODE_SIGNING_ALLOWED=NO' in script and 'CODE_SIGNING_REQUIRED=NO' in script
    assert 'devicectl' not in script and 'simctl' not in script and 'allowProvisioningUpdates' not in script
    assert "'release_authorized':False" in script and 'COMPILE_LINK_ONLY_PASS' in script
    assert 'CGoInvoke CGoFree tun2proxy_run_with_cli_args' in script


def test_runner_scope_and_terminal_reconciliation_require_independent_receipt():
    runner=(IOS/'PacketTunnel/NativeXrayPacketSession.swift').read_text()
    assert runner.startswith('#if (DEBUG || APL_NATIVE_PRODUCT_RUNTIME) && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_XRAY_CANDIDATE\n')
    assert 'route.remoteAddress=="192.168.1.80"' in runner
    assert 'destinationAddress:"198.51.100.77"' in runner and 'destinationAddress:"2001:db8:77::77"' in runner
    assert 'NEIPv4Route.default' not in runner and '.dnsSettings' not in runner
    assert 'tun2proxy_run_with_cli_args' in runner and 'drainOwnedRustRunner' in runner
    assert 'control.ready()' not in runner
    assert 'control.finishDrain()' in runner and 'control.fail()' in runner
    provider=(IOS/'PacketTunnel/PacketTunnelProvider.swift').read_text()
    assert 'NativeXrayPacketSession(' not in provider  # still no runtime-start caller
    app=(IOS/'App/VPNController.swift').read_text()
    assert 'target.connection.sendProviderMessage(bytes)' in app
    assert 'dispatch.acceptTerminalDrain' in app and 'dispatch.finishAfterTerminalDrain' in app
    assert 'target.connection.status == .disconnected' in app
    core=(IOS/'SharedCore/NativeSessionLaunchBoundary.swift').read_text()
    assert 'response.matches(request),response.state == .drained' in core


def test_awg_product_candidate_is_a_separate_non_network_validation_lane():
    driver=(IOS/'PacketTunnel/NativeAWGValidationDriver.swift').read_text()
    assert driver.startswith('#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_AWG_CANDIDATE\n')
    assert '#error(' in driver and 'aplAWGBridgeValidateConfig' in driver
    assert 'aplAWGBridgeStart(' not in driver and '4096' in driver
    provider=(IOS/'PacketTunnel/PacketTunnelProvider.swift').read_text()
    assert '#elseif APL_NATIVE_AWG_CANDIDATE' in provider
    assert 'inspectConfiguration:NativeAWGValidationDriver.validate' in provider
    assert 'APL_NATIVE_AWG_CANDIDATE' not in (IOS/'project.yml').read_text()
    go=(IOS/'Tools/AWGNativeLab/product_config_validation.go').read_text()
    assert 'validationOnlyBind' in go and 'b.attempted.Store(true)' in go
    assert 'd.IpcSet(string(raw))' in go and 'd.Close()' in go
    assert 'd.Up()' not in go and 'net.Listen' not in go and 'net.Dial' not in go
    script=(IOS/'Tools/build_product_awg_candidate_unsigned.sh').read_text()
    assert 'GOPROXY=off' in script and 'CODE_SIGNING_ALLOWED=NO' in script
    assert 'APL_NATIVE_XRAY_CANDIDATE' not in script and "'release_authorized':False" in script
    assert "_CGoInvoke$" in script


def test_actual_provider_synthetic_runtime_is_separate_and_not_ready_claim():
    provider=(IOS/'PacketTunnel/PacketTunnelProvider.swift').read_text()
    gate='#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_SYNTHETIC_RUNTIME'
    assert gate in provider
    assert 'syntheticOwner.start(provider:self' in provider and 'syntheticOwner.stop(provider:self)' in provider
    assert 'syntheticOwner.message(messageData,provider:self)' in provider
    owner=(IOS/'PacketTunnel/NativeSyntheticProviderSession.swift').read_text()
    assert owner.startswith(gate+'\n')
    assert 'Self.selection.claim' in owner and 'guard !used,!retired' in owner
    assert 'ExactLabTUNDescriptor.find(address:"192.0.2.177")' in owner
    assert 'control.ready()' not in owner and 'ProfileStore' not in owner
    assert 'await session.respond(request,provider:provider)' in owner
    assert 'APL_NATIVE_SYNTHETIC_RUNTIME' not in (IOS/'project.yml').read_text()
    for engine in ('xray','awg'):
        script=(IOS/f'Tools/build_product_{engine}_candidate_unsigned.sh').read_text()
        assert 'APL_COMPILE_SYNTHETIC_RUNTIME:-0' in script
        assert 'synthetic_runtime_compiled' in script and 'fixture_origins' in script
    awg=(IOS/'PacketTunnel/NativeAWGPacketSession.swift').read_text()
    assert 'AWGPacketFlowPump(flow:provider.packetFlow)' in awg
    assert 'pump.stop(completion:done)' in awg and 'control.finishDrain()' in awg
    assert 'control.ready()' not in awg and 'NEIPv4Route.default' not in awg and '.dnsSettings' not in awg


def test_unified_go_archive_is_compile_only_and_pinned():
    script=(IOS/'Tools/build_unified_go_candidate_unsigned.sh').read_text()
    assert 'GOPROXY=off GOSUMDB=off' in script and 'mod verify' in script
    assert 'build -mod=readonly' in script and '-buildmode=c-archive' in script
    assert 'b5928efb6ca19f0153958460c3d141f04abc5c2e' in script
    assert 'func awgSyntheticCLI() {' in script
    assert 'CGoInvoke CGoFree aplAWGBridgeValidateConfig aplAWGBridgeStartLAN aplAWGBridgePush aplAWGBridgePull aplAWGBridgeStop' in script
    assert "'release_authorized':False" in script
    assert 'devicectl' not in script and 'simctl' not in script and 'codesign' not in script
    assert 'mv "$E" "$out"' in script and 'ios-unified-link-probe' not in script.split('mkdir -p "$work/src" "$work/evidence"')[1].split('mv "$E" "$out"')[-1]


def test_unified_product_links_one_go_archive_and_uses_process_selector():
    script=(IOS/'Tools/build_product_unified_candidate_unsigned.sh').read_text()
    assert '57b279f366b47fd27a46b201088a997fb03f68205f5189dc2931ae43f00011e6' in script
    assert 'module APLUnifiedGo' in script and '-lAPLUnified -ltun2proxy' in script
    assert '-lXray' not in script and '-lAWG ' not in script
    assert 'CODE_SIGNING_ALLOWED=NO' in script and "'release_authorized':False" in script
    owner=(IOS/'PacketTunnel/NativeSyntheticProviderSession.swift').read_text()
    assert 'private static var selection=NativeSyntheticEngineSelection()' in owner
    assert 'Self.selection.claim' in owner and 'switch request.binding.reference.kind.provider' in owner
    assert 'APL_NATIVE_UNIFIED_GO_CANDIDATE' not in (IOS/'project.yml').read_text()
    host=(IOS/'Tools/NativeSyntheticProductControlHost.swift').read_text()
    assert 'externalQuiescenceConfirmed' in host and 'try await censusOff()' in host
    assert 'reply.matches(request)' in host and 'reply.state == .starting' in host
    assert 'stale.state == .rejected' in host and 'reply.state == .drained' in host
    assert 'saveToPreferences' not in host and 'ProfileStore' not in host
    assert all('NativeSyntheticProductControlHost' not in p.read_text() for p in (IOS/'App').glob('*.swift'))
