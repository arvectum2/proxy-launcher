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


def test_native_app_dispatch_stays_gated_and_never_creates_manager():
    app=(IOS/'App/VPNController.swift').read_text()
    section=app[app.index('func submitNativeCredentialValidation'):app.index('private static let productConfigurationName')]
    assert 'named.count==1' in section and 'mode.owns(proto,owner:owner)' in section
    assert 'connection.startTunnel(options:$0)' in section
    assert 'loadAllManagers(requireResult:true)' in section and 'nativeValidationPolicyIsEmpty()' in section
    assert 'try dispatch.abortBeforeSubmission()' in section
    assert 'if !dispatch.attempted' in section
    assert 'saveToPreferences' not in section and 'NETunnelProviderManager()' not in section
    assert app.count('func submitNativeCredentialValidation')==1
    assert sum(p.read_text().count('submitNativeCredentialValidation(') for p in (IOS/'App').glob('*.swift'))==1
    assert 'guard Self.operationGate.active != .nativeValidation else{return}' in app

def test_runtime_review_uses_same_owned_lease_without_ordinary_caller():
    app=(IOS/'App/VPNController.swift').read_text()
    section=app[app.index('func submitNativeCredentialValidation'):app.index('private static let productConfigurationName')]
    assert '#if APL_NATIVE_PRODUCT_RUNTIME_REVIEW' in section
    assert 'dispatch.submitRuntimeReview(' in section and 'try dispatch.finishAfterTerminalDrain' in section
    assert 'let before=try await loadAllManagers(requireResult:true)' in section
    assert 'let afterDrain=try await loadAllManagers(requireResult:true)' in section
    assert 'NativeRuntimeReviewRequest.ownsConfiguration' in app
    assert sum(p.read_text().count('submitNativeRuntimeReview(') for p in (IOS/'App').glob('*.swift') if p.name!='NativeRuntimeReviewQAView.swift')==1
    harness=(IOS/'App/NativeRuntimeReviewQAView.swift').read_text()
    assert harness.count('submitNativeRuntimeReview(')==1 and 'APL_NATIVE_RUNTIME_QA_HARNESS' in harness.splitlines()[0]
    assert 'if NativeRuntimeReviewQAView.enabled' in (IOS/'App/ArvectumProxyLauncherApp.swift').read_text()
    assert 'APL_NATIVE_RUNTIME_QA_HARNESS' not in (IOS/'project.yml').read_text()
    assert 'guard authorized(),Self.nativeValidationDispatch==nil' in app and 'guard known.isEmpty' in app
    assert 'nativeRuntimeQAFixtureIsIsolated' in app and 'try await item.removeFromPreferences()' in app
    assert 'independentWitnessRequired=true' in harness and 'releaseAuthorized=false' in harness
    assert 'readAndConsume' in harness and '.withoutOverwriting' in harness
    assert 'proto.proxySettings==nil && !proto.includeAllNetworks && !proto.enforceRoutes' in section
    assert 'saveToPreferences' not in section and 'NETunnelProviderManager()' not in section


def test_product_lane_is_explicit_and_keeps_review_and_legacy_separate():
    app=(IOS/'App/VPNController.swift').read_text()
    product=app[app.index('private func connectProduct'):app.index('private func connectWithLease')]
    assert 'allOff(refreshed)' in product and 'ownsProductManager(readback,owner:owner)' in product
    assert 'store.issueNativeProductLaunch(selection,owner:owner)' in product
    assert 'session.startTunnel(options:launch.options)' in product and 'connectWithLease()' not in product
    provider=(IOS/'PacketTunnel/PacketTunnelProvider.swift').read_text()
    start=provider[provider.index('override func startTunnel'):provider.index('override func stopTunnel')]
    assert start.index('NativeProductStartRequest.inspect') < start.index('NativeProviderStartRequest.inspect')
    assert 'productionLane.reserveNative()' in start and 'productionLane.reserveLegacy()' in start
    assert 'protocolConfiguration.serverAddress != "APL Native Product"' in start
    owner=(IOS/'PacketTunnel/NativeProductRuntimeOwner.swift').read_text()
    assert 'guard try store.nativeProductOwner()==request.owner' in owner
    assert 'runner.startFull(provider:provider,candidate:plan)' in owner
    assert 'Product runtime cannot contain lab or link preparation modes' in owner
    assert 'APL_NATIVE_PRODUCT_RUNTIME' not in (IOS/'project.yml').read_text()
