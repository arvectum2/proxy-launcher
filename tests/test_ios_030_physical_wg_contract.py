"""Guard exact physical synthetic WG scope and independent receipts."""
from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/"mobile/ios"
LAB=IOS/"Tools/NativeTunnelLab"

def test_wg_physical_only_explicit_endpoint_and_dual_host_routes():
    cfg=(IOS/"Tools/XrayWireGuardLabConfig.swift").read_text()
    assert 'physical: Bool = false' in cfg
    assert 'physical ? "192.168.1.80:39881" : "127.0.0.1:39881"' in cfg
    assert 'preview.format == .wireGuard' in cfg
    assert 'Set(preview.peers[0].allowedIPs) == Set(targets)' in cfg
    assert '"freedom"' not in cfg
    provider=(LAB/"NativeLabPacketTunnelProvider.swift").read_text()
    assert 'mode == "wg-dual"' in provider and 'dual:true,physical:true' in provider
    assert 'NEIPv6Route(destinationAddress:"2001:db8:77::77",networkPrefixLength:128)' in provider
    assert 'NEIPv6Route.default()' not in provider and 'NEIPv4Route.default()' not in provider
    assert 'require-connected-udp' in (LAB/"build_unsigned.sh").read_text()

def test_actual_dual_probes_bounded_and_independently_witnessed():
    host=(LAB/"Host/NativeLabHost.swift").read_text()
    assert 'connection.receiveMessage' in host and 'queue.asyncAfter(deadline:.now()+5)' in host
    assert '"tcp4","tcp6","udp4","udp6"' in host
    runner=(LAB/"run_physical_wg.py").read_text()
    assert 'WG_PHYSICAL_PREFLIGHT' in runner and 'total==1+int(expected)' in runner
    assert 'diff["out",2]==0 and diff["out",4]==0' in runner
    assert 'client[0]!=src' in runner and 'sum(counts.values())>=512' in runner
    assert 'if not a.approved' in runner
    assert 'reference.resolve()' in runner
