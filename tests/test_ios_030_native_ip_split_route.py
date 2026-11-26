from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/'mobile/ios'


def test_explicit_ip_review_never_activates_or_replaces_stored_policy():
    core=(IOS/'SharedCore/NativeIPSplitRoutePlan.swift').read_text()
    assert 'explicitIPOptIn' in core and 'existingPolicy == .tunnelOnly' in core
    assert 'protect.contains(where:{rule.overlaps($0)})' in core
    assert 'inet_pton' in core and 'getaddrinfo' not in core
    settings=(IOS/'Shared/NativeTunnelNetworkSettings.swift').read_text()
    assert '#if DEBUG && APL_NATIVE_IP_ROUTE_REVIEW' in settings
    assert 'makeExplicitIPReview' in settings and 'NEIPv4Route' in settings and 'NEIPv6Route' in settings
    assert not any('makeExplicitIPReview' in p.read_text() for p in (IOS/'PacketTunnel').glob('*.swift'))
    assert 'APL_NATIVE_IP_ROUTE_REVIEW' not in (IOS/'project.yml').read_text()
    view=(IOS/'App/NativePersistentProfilesView.swift').read_text()
    assert 'row.reference.kind != .vlessReality' in view or '$0.reference.kind != .vlessReality' in view
    assert 'model.vpn.withNativeLibraryWrite' in view and 'session.previewIPRoutes' in view
    assert 'generation==token,lifecycle.visible,phase == .active,ipOptIn' in view
    assert 'setTunnelNetworkSettings(' not in view and 'startTunnel(' not in view
    assert 'ipPreview=nil;ipOptIn=false;ipRuleText=""' in view
