from pathlib import Path

IOS=Path(__file__).resolve().parents[1]/"mobile/ios"
QA=IOS/"Tools/ProviderVLESSHardwareQA"
def test_real_product_runtime_in_separate_signed_lab_only():
    provider=(QA/"ProductRunnerProvider.swift").read_text()
    runner=(IOS/"PacketTunnel/NativeXrayPacketSession.swift").read_text()
    build=(QA/"build_unsigned.sh").read_text()
    assert '#if APL_ISOLATED_PRODUCT_RUNNER_QA' in provider
    assert 'NativeCredentialRecord.create(profileID:UUID()' in provider
    assert 'record.compileFullTunnelCandidate(admission:.tunnelOnly,exactDNSAvailable:true)' in provider
    assert 'try await owned.startFull(provider:self,candidate:candidate)' in provider
    assert 'try await runner.stop(provider:self,removeSettings:false)' in provider
    assert 'try? await runner.stop(provider:self,removeSettings:true)' in provider
    assert '20_000_000_000' in provider
    assert 'parsed.serverHost=="192.168.1.80"' in provider
    assert 'parsed.serverPort==39882' in provider
    assert 'options?["aplFixedWitnessKind"] as? String=="tcp4"' in provider
    assert 'FullRouteGuard.restrict(boundConfiguration,kind:.tcp4)' in runner
    assert '#else\n        let configurationForStart=boundConfiguration' in runner
    assert 'let name = try await physicalUnderlayInterface()' in runner
    assert 'configuration:configurationForStart' in runner
    assert 'NativeXrayPacketSession.swift' in build and 'NativeXrayRuntimeDriver.swift' in build
    assert 'rm "$out/Sources/Provider.swift"' in build
    assert 'APL_ISOLATED_PRODUCT_RUNNER_QA' not in (IOS/"project.yml").read_text()
    assert 'APL_ISOLATED_PRODUCT_RUNNER_QA' not in (IOS/"Tools/stage_ios_030_release_candidate.py").read_text()
    for forbidden in ('SecItem','UserDefaults','ProfileStore()','NativeLabRuntime.call','tun2proxy_run_with_cli_args'):
        assert forbidden not in provider

def test_product_runner_receipt_cannot_be_claimed_from_legacy_lab():
    p=(QA/"ProductRunnerProvider.swift").read_text()
    assert p.index('try await runner.stop(provider:self,removeSettings:false)')<p.index('"actualProductRunner":true')
    assert '"releaseAuthorized":false' in p
    assert '"nativeStopConfirmed":true' in p
    assert 'catch{completionHandler?(nil)' in p
