from pathlib import Path
import re
IOS=Path(__file__).resolve().parents[1]/"mobile/ios"
def source(p):return (IOS/p).read_text()
def test_ordinary_ui_qa_is_isolated_and_not_public():
    store=source("Shared/ProfileStore.swift")
    block=store.split("#if APL_PRODUCT_UI_QA",1)[1].split("#else",1)[0]
    original=store.split("#else\n    private enum Key",1)[1].split("private let defaults:",1)[0]
    qa=dict(re.findall(r'static let (\w+) = "([^"]+)"',block))
    prod=set(re.findall(r'static let (\w+) = "',original))
    assert set(qa)==prod
    assert all(x.startswith("qa_ordinary_ui.") for x in qa.values())
    assert 'Key.all.allSatisfy' in block
    assert 'for key in Key.all' in block
    assert "synthetic-ui-qa." in source("Shared/AppShared.swift")
    assert "synthetic-ui-qa.subscription" in source("App/ProxySubscriptionStore.swift")
    assert 'qa_ordinary_ui.tunnel_events_v1' in source("Shared/TelemetryStore.swift")
    assert "APL Native Product Synthetic UI QA" in source("App/VPNController.swift")
    assert "#if APL_PRODUCT_UI_QA\n                // Ordinary startup" in source("App/VPNController.swift")
    assert "APL_PRODUCT_UI_QA" not in source("project.yml")
    assert "'APL_PRODUCT_UI_QA'" in source("Tools/stage_ios_030_release_candidate.py")
    ads=source("App/SettingsBannerView.swift")
    assert "#if APL_PRODUCT_UI_QA" in ads and "static let isEnabled = true" in ads
def test_actual_screens_and_user_action_evidence():
    v=source("App/ProductOrdinaryUIQAView.swift")
    assert 'ContentView()' in v
    assert 'ProxyImportView(initialSource:context.input.fixture)' in v
    assert '.defaultAppStorage(context.preferences)' in v
    assert 'snapshot.selected==nil' in v and 'guard imported,selection.reference==ref' in v
    assert 'model.qaUIToggleStarts==1' in v and 'model.qaUIToggleStops==1' in v
    assert 'ScopedTCPWitness.run(nonce)' in v
    assert 'ticketConsumed=try NativeCredentialKeychain' in v
    assert 'try await vpn.connect()' not in v and 'startVPNTunnel' not in v
    assert 'qaOffCensus()' in v
    assert v.index('encode(journal).write(to:journalURL')<v.index('store.qaInstallSyntheticOwner')
    assert 'guard refs.count<=1' in v and 'digest(record)==expected' in v
    assert 'vpn.qaStopOwnedManager(owner:journal.owner)' in v
    assert 'vpn.qaRemoveManager(owner:journal.owner,baseline:journal.baseline)' in v
    assert 'qaRemoveEmptyCatalog()' in v and 'qaUIClearIsolatedPreferences()' in v
    assert '"--apl-authorized-product-ui-cleanup"' in v
    assert 'releaseAuthorized":false' in v


def test_physical_ui_runner_waits_for_independent_peer():
    v=source("App/ProductOrdinaryUIQAView.swift")
    x=source("Tests/UITests/PhysicalProductOrdinaryUIQATests.swift")
    assert "value.runID==context.input.runID,value.ready" in v
    assert "selected && !peerReady" in v
    assert 'selected,peerReady,model.qaUIToggleStarts==1' in v
    assert 'APL_RUN_EXPLICIT_PRODUCT_UI_QA && !targetEnvironment(simulator)' in x
    for token in ('review.tap()','save.tap()','select.tap()','confirm.tap()','connect.tap()','stop.tap()','clean.tap()'):
        assert token in x
    assert x.index('Peer ready — tap Home Connect')<x.index('connect.tap()')
    assert x.index('Receipt PASS — tap Home Disconnect')<x.index('stop.tap()',x.index('Receipt PASS — tap Home Disconnect'))
    assert 'APL_RUN_EXPLICIT_PRODUCT_UI_QA' not in source("project.yml")
