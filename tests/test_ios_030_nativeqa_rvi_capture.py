import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"mobile/ios/Tools"))
from capture_nativeqa_rvi import summarize

STATS="listening on rvi0, link-type PKTAP (Apple DLT_PKTAP)\n1 packet captured\n0 packets dropped by kernel\n"
TARGET=("198.51.100.77",39883)
ROW="1234.5 (en0, out) IP 192.0.2.254.54321 > 198.51.100.77.39883: UDP, length 48\n"

def test_physical_metadata_and_tunnel_not_confused():
    a=summarize(ROW,STATS,TARGET,1234,1235)
    assert a==dict(physicalOut=1,tunnelOut=0,ambiguous=0,complete=True)
    b=summarize(ROW.replace("en0","utun8"),STATS,TARGET,1234,1235)
    assert b["physicalOut"]==0 and b["tunnelOut"]==1 and b["complete"]

def test_ipv6_and_cellular():
    row="1234.5 (pdp_ip0, out) IP6 2001:db8::1.54321 > 2001:db8:77::77.39883: UDP, length 48\n"
    v=summarize(row,STATS,("2001:db8:77::77",39883),1234,1235)
    assert v["physicalOut"]==1 and v["complete"]

def test_unknown_metadata_loss_or_invalid_window_is_inconclusive():
    for row in (ROW.replace("en0","unknown0"),ROW.replace("(en0, out) ",""),ROW.replace("out","in"),ROW.replace("1234.5","1000.0")):
        assert not summarize(row,STATS,TARGET,1234,1235)["complete"]
    assert not summarize(ROW,STATS.replace("0 packets dropped","1 packet dropped"),TARGET,1234,1235)["complete"]
    assert not summarize("",STATS,TARGET,1234,1235)["complete"]

def test_awg_exact_target_selection_and_off_control():
    import pytest
    import native_runtime_qa_receipt as q
    from capture_nativeqa_rvi import target_for
    def make(kind, action, scope, probe, mode):
        fixture=dict(schema=1, reference=dict(kind=kind,profileID=q.new_id(),revision=q.new_id()))
        return q.make_command(fixture,q.new_id(),action,scope,probe,mode)
    for probe,target in (("udp4",("192.0.2.2",39892)),("udp6",("2001:db8::2",39892)),("dns4",("192.0.2.53",53))):
        c=make("amneziaWG1","run",None,probe,"positive")
        assert target_for(c)==target
        off=make("amneziaWG1","offControl",None,"dnsWire4" if probe=="dns4" else probe,"observe-off")
        assert target_for(off)==target and len(off["nonce"])==48
        with pytest.raises(ValueError): q.validate_command(dict(off,nonce="a"*40))
        with pytest.raises(ValueError): q.validate_command(dict(off,scope="wireGuardFull"))
    assert target_for(make("wireGuard","run","wireGuardFull","udp4","positive"))==TARGET
    for c in (make("amneziaWG1","run",None,"udp4","wrong-key"),make("amneziaWG1","run",None,"tcp4","positive"),make("vlessReality","run","vlessDatagrams","udp4","positive")):
        with pytest.raises(ValueError): target_for(c)
