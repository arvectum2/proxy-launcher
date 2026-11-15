from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/'mobile/ios'


def test_concrete_xray_abi_only_under_explicit_candidate_gate():
    driver=(IOS/'PacketTunnel/NativeXrayRuntimeDriver.swift').read_text()
    assert driver.startswith('#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_XRAY_CANDIDATE\n')
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
