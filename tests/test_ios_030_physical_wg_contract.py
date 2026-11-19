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


def test_clean_loopback_candidate_keeps_production_patch_unchanged():
    candidate=(LAB/"tun2proxy-connected-udp-loopback-clean.patch").read_text()
    assert "a.ip().is_loopback()" in candidate
    assert "Ipv4Addr::LOCALHOST" in candidate and "Ipv6Addr::LOCALHOST" in candidate
    assert "APL_UDP_BIND_ERROR" not in candidate and "APL_UDP_SEND_ERROR" not in candidate
    assert "udp_server.send(&s5_udp_data).await?" in candidate
    assert "LabUDPAssociationDiagnostic" not in (LAB/"NativeLabPacketTunnelProvider.swift").read_text()
    assert "if cfg.Measure" in (IOS/"Tools/WGReferenceLab/main.go").read_text()
    assert "--with-simulator" in (LAB/"build_udp_candidate.sh").read_text()


def test_clean_stability_requires_prepared_off_and_no_retries():
    script=(LAB/"run_clean_wg_stability.sh").read_text()
    assert 'a["runID"]==b["runID"]' in script
    assert 'a["stage"]=="labPreparedOff"' in script
    assert 'b["connected"] is False' in script
    assert 'for kind in tcp4 udp4 udp6 udp4 udp6 udp4 udp6 tcp6' in script
    assert '--kind tcp4 --wrong-key --retain-profile' in script
    assert 'run_physical_peer.py' in script and '--mode positive' in script
    assert 'assert_no_extension' in script
    assert 'set -euo pipefail' in script
    assert '--prepare-only' not in script
