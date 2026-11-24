from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/"mobile/ios"
def source(path):return (IOS/path).read_text()
def test_namespace_and_release_isolation():
    assert 'synthetic-owner-qa.' in source("Shared/AppShared.swift")
    assert 'qa_synthetic_native_product_selection.v1' in source("Shared/ProfileStore.swift")
    assert 'qa_synthetic_native_product_owner.v1' in source("Shared/ProfileStore.swift")
    assert 'qa_synthetic_tunnel_events_v1' in source("Shared/TelemetryStore.swift")
    assert 'APL Native Product Synthetic QA' in source("App/VPNController.swift")
    assert 'APL_PRODUCT_OWNER_QA' not in source("project.yml")
    assert "'APL_PRODUCT_OWNER_QA'" in source("Tools/stage_ios_030_release_candidate.py")
    assert '#if APL_PRODUCT_OWNER_QA\n@main' in source("App/ArvectumProxyLauncherApp.swift")
def test_exact_ticket_and_transport_path():
    p=source("App/ProductOwnerQAView.swift")
    assert 'try await vpn.connect()' in p
    assert 'launch.ticket.purpose == .productStart' in p
    assert 'receipt["ticketConsumed"]=try handoff.handoffAccountsForValidation().isEmpty' in p
    assert 'ScopedTCPWitness.run(nonce)' in p
    assert 'receipt["nativeDrain"]=try await vpn.qaDrain()' in p
    assert 'response.matches(request) && response.state == .drained' in source("App/VPNController.swift")
    assert 'FullRouteGuard.restrict(boundConfiguration,kind:.tcp4)' in source("PacketTunnel/NativeXrayPacketSession.swift")
    assert 'APL_ISOLATED_PRODUCT_RUNNER_QA || APL_PRODUCT_OWNER_QA' in source("PacketTunnel/NativeXrayPacketSession.swift")
    assert 'plan.route.remoteAddress=="192.168.1.80"' in source("PacketTunnel/NativeProductRuntimeOwner.swift")
    assert 'let setupBudget:UInt64=20_000_000_000' in source("PacketTunnel/NativeProductRuntimeOwner.swift")
def test_journal_before_mutation_and_owned_cleanup():
    p=source("App/ProductOwnerQAView.swift")
    assert p.index('encode(entry).write(to:journal')<p.index('store.qaInstallSyntheticOwner(owner)')
    assert 'original==NativeCredentialCatalogReader.Snapshot.empty' in p
    assert 'try await vpn.qaStopOwnedManager(owner:j.owner)' in p
    assert 'try await vpn.qaRemoveManager(owner:j.owner,baseline:j.baseline)' in p
    assert 'snap.current.allSatisfy({$0==j.reference})' in p
    assert 'snap.retired.allSatisfy({$0==j.reference})' in p
    assert 'guard accounts.count<=1' in p
    assert 'qaRemoveEmptyCatalog()' in p
    assert 'qaRemoveSyntheticOwner(j.owner)' in p
    assert 'guard try await qaOffCensus()==baseline' in source("App/VPNController.swift")
    assert 'owned.allSatisfy({productManagerMatchesOwner($0,owner:owner)})' in source("App/VPNController.swift")
