"""Passive Smart 3.0 UI diagnostic notification must be local and opt-in-free."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'mobile/ios'
CONTENT = (ROOT/'App/ContentView.swift').read_text()
MODEL = (ROOT/'App/AppViewModel.swift').read_text()
POLICY = (ROOT/'SharedCore/AdaptiveRouteLearning.swift').read_text()


def test_problem_badge_refreshes_from_appgroup_on_return_not_background_polling():
    assert 'scenePhase) private var scenePhase' in CONTENT
    assert 'if phase == .active { model.refresh() }' in CONTENT
    assert '.badge(model.pendingSmartDiagnosticsCount)' in CONTENT
    assert 'var pendingSmartDiagnosticsCount: Int' in MODEL
    assert 'adaptiveRouteLearning.diagnosticCandidates().count' in MODEL
    assert 'adaptiveRouteLearning = store.adaptiveRouteLearning' in MODEL
    assert '.onReceive(Timer' not in CONTENT


def test_never_creates_direct_routes_or_shows_stale_problem_on_badge():
    assert 'record.sessionIDs.count >= 2' in POLICY
    assert 'now.timeIntervalSince(record.last) <= Self.window' in POLICY
    assert '!rejected.contains(host)' in POLICY
    assert 'AdaptiveDirectProbe' not in CONTENT
