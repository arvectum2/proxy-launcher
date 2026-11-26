from pathlib import Path

IOS=Path(__file__).resolve().parents[1]/'mobile/ios'


def test_refresh_review_is_offline_and_not_activated():
    code=(IOS/'SharedCore/ProxySubscriptionRefreshReview.swift').read_text()
    for forbidden in ('URLSession','BGTaskScheduler','UserDefaults','SecItem','NetworkExtension','saveProfile','Task.sleep'):
        assert forbidden not in code
    assert 'guard foreground,userInitiated' in code
    assert 'existing==p.baseline' in code
    assert 'currentSource==summary.request.source' in code
    for folder in ('App','PacketTunnel','Shared'):
        assert all('ProxySubscriptionRefreshReview' not in path.read_text() for path in (IOS/folder).rglob('*.swift'))
    assert 'BackgroundTasks' not in (IOS/'App/ProxySubscriptionFetch.swift').read_text()
