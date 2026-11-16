import copy
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "mobile/ios/Tools"))
import native_runtime_qa_receipt as q
from validate_unified_synthetic_receipt import read


def fixture(kind="wireGuard"):
    return {"schema": 1, "reference": {"kind": kind, "profileID": q.new_id(), "revision": q.new_id()}}


def command(kind="wireGuard", probe="tcp4", mode="positive", scope="wireGuardFull"):
    return q.make_command(fixture(kind), q.new_id(), "run", scope, probe, mode)


def receipt(c):
    r = {k: copy.deepcopy(c[k]) for k in ("schema", *q.BINDING, *q.OPTIONAL) if k in c}
    r.update(setup=[], probeAttempted=False, managerReadback=True, osOff=True, independentWitnessRequired=True, releaseAuthorized=False)
    if c["action"] == "run":
        ident = dict(epoch=q.new_id(), generation=1, provider="standalone-awg" if c["reference"]["kind"] == "amneziaWG1" else "rust-xray")
        stale = dict(ident, epoch=q.new_id())
        def exchange(identity, action, state):
            req = dict(version=1, id=q.new_id(), identity=identity.copy(), action=action)
            return dict(request=req, response=copy.deepcopy(dict(req, state=state)))
        r.update(setup=[exchange(ident, "observe", "starting"), exchange(stale, "observe", "rejected")], drain=exchange(ident, "drain", "drained"), probeAttempted=True)
        if c["mode"] == "positive":
            r["responseSHA256"] = q.sha((("APL:" if c["reference"]["kind"]=="amneziaWG1" else "APL_RECEIPT:")+c["nonce"]).encode())
    return r


@pytest.mark.parametrize("kind,scope,mode", [
    ("wireGuard", "wireGuardFull", "positive"), ("wireGuard","wireGuardFull","wrong-key"),
    ("vlessReality","vlessDatagrams","positive"), ("vlessReality","vlessDatagrams","wrong-key"),
    ("amneziaWG1",None,"positive"), ("amneziaWG1",None,"wrong-key"), ("amneziaWG1",None,"wrong-psk")])
@pytest.mark.parametrize("probe", q.PROBES)
def test_run_receipt(kind, scope, mode, probe):
    c = command(kind, probe, mode, scope)
    out = q.verify_host(c, receipt(c))
    assert out["status"] == "host_receipt_correlated_only"
    assert out["independent_witness_required"] and not out["release_authorized"] and not out["runtime_authorized"]
    assert c["nonce"] not in str(out)


@pytest.mark.parametrize("action", ("prepareManager", "readManager", "removeManager"))
def test_manager_only(action):
    c = q.make_command(fixture(), q.new_id(), action)
    assert "nonce" not in c
    assert q.verify_host(c, receipt(c))["action"] == action
    r = receipt(c)
    r["probeAttempted"] = True
    with pytest.raises(ValueError):
        q.verify_host(c, r)


@pytest.mark.parametrize("change", [
    lambda r: r.update(requestID=q.new_id()), lambda r: r.update(owner=q.new_id()),
    lambda r: r["reference"].update(revision=q.new_id()), lambda r: r.update(probe="udp6"),
    lambda r: r.update(osOff=False), lambda r: r.update(managerReadback=False),
    lambda r: r.update(releaseAuthorized=True), lambda r: r.update(independentWitnessRequired=False),
    lambda r: r.update(probeAttempted=False), lambda r: r.update(setup=[]),
    lambda r: r.pop("drain"), lambda r: r.update(responseSHA256="0"*64),
    lambda r: r["setup"][0]["response"].update(state="ready"),
    lambda r: r["setup"][1]["response"].update(state="starting"),
    lambda r: r["drain"]["response"].update(state="draining"),
    lambda r: r["drain"]["request"].update(identity=dict(r["drain"]["request"]["identity"],epoch=q.new_id())),
    lambda r: r["setup"][0]["request"].update(version=True),
    lambda r: r.update(schema=True), lambda r: r.update(unexpected=True),
    lambda r: r["setup"][1].update(request=copy.deepcopy(r["setup"][0]["request"])),
    lambda r: r["setup"][1]["request"].update(id=r["setup"][0]["request"]["id"]),
])
def test_reject_malformed(change):
    c = command()
    r = receipt(c)
    change(r)
    with pytest.raises(ValueError):
        q.verify_host(c,r)


def test_stale_epoch_and_replay():
    a = command()
    b = command()
    with pytest.raises(ValueError):
        q.verify_host(b, receipt(a))
    r = receipt(a)
    live = r["setup"][0]["request"]["identity"]
    r["setup"][1]["request"]["identity"] = live
    r["setup"][1]["response"]["identity"] = live.copy()
    with pytest.raises(ValueError):
        q.verify_host(a,r)
    r = receipt(a)
    repeated = r["setup"][0]["request"]["id"]
    r["drain"]["request"]["id"] = repeated
    r["drain"]["response"]["id"] = repeated
    with pytest.raises(ValueError):
        q.verify_host(a,r)


@pytest.mark.parametrize("kind,scope,probe,mode", [
    ("wireGuard",None,"udp4","positive"), ("wireGuard","vlessDatagrams","tcp4","positive"),
    ("vlessReality","wireGuardFull","tcp4","positive"), ("vlessReality",None,"tcp6","positive"),
    ("amneziaWG1","wireGuardFull","tcp4","positive"), ("wireGuard","wireGuardFull","tcp4","wrong-psk"),
    ("vlessReality","vlessDatagrams","udp4","wrong-psk"), ("amneziaWG1",None,"icmp","positive"),
])
def test_invalid_command(kind,scope,probe,mode):
    with pytest.raises(ValueError):
        command(kind,probe,mode,scope)


def test_private_exclusive_output(tmp_path):
    root=tmp_path/"private"
    root.mkdir(mode=0o700)
    output=root/"command.json"
    c=command()
    q.command_file(output,c)
    assert output.stat().st_mode & 0o777 == 0o600
    assert read(output)==c
    with pytest.raises(FileExistsError):
        q.command_file(output,command())
    link=root/"link.json"
    link.symlink_to(output)
    with pytest.raises(FileExistsError):
        q.command_file(link,c)
    root.chmod(0o755)
    with pytest.raises(ValueError):
        q.command_file(root/"public.json",c)


@pytest.mark.parametrize("kind", q.KINDS)
@pytest.mark.parametrize("probe", q.PROBES)
def test_physical_qa_wire_contract_on_loopback(kind, probe):
    import socket
    import threading
    from unified_loopback_witness import LoopbackWitness
    c = command(kind, probe, "positive", {"wireGuard":"wireGuardFull","vlessReality":"vlessDatagrams","amneziaWG1":None}[kind])
    nonce=c["nonce"]
    w=LoopbackWitness(kind,probe,nonce,physical_qa_contract=True)
    family=socket.AF_INET if probe.endswith("4") else socket.AF_INET6
    udp=probe.startswith("udp")
    awg=kind=="amneziaWG1"
    if awg:
        request=nonce.encode()
    elif udp:
        request=("APL_UDP:"+nonce).encode()
    else:
        authority="198.51.100.77:39883" if family==socket.AF_INET else "[2001:db8:77::77]:39883"
        request=("GET /"+nonce+" HTTP/1.1\r\nHost: "+authority+"\r\nConnection: close\r\n\r\n").encode()
    expected=(("APL:" if awg else "APL_RECEIPT:")+nonce).encode()
    with socket.socket(family,socket.SOCK_DGRAM if udp else socket.SOCK_STREAM) as server:
        server.bind(("127.0.0.1" if family==socket.AF_INET else "::1",0))
        if not udp:
            server.listen(1)
        with socket.socket(family,server.type) as client:
            client.settimeout(2)
            t=threading.Thread(target=w.serve,args=(server,1))
            t.start()
            try:
                client.connect(server.getsockname())
                client.sendall(request)
                response=client.recv(512)
                if not (awg or udp):
                    while True:
                        data=client.recv(512)
                        if not data:break
                        response+=data
                    headers,response=response.split(b"\r\n\r\n",1)
                    assert headers.startswith(b"HTTP/1.1 200 ")
                assert response==expected
            finally:
                t.join(3)
            assert not t.is_alive()
            obs=w.observation()
            assert obs["matches"]==obs["responses"]==1
            assert obs["responseSHA256"]==receipt(c)["responseSHA256"]
            assert not obs["runtime_authorized"]


def test_exact_hostname_probe_only_for_positive_full_route():
    c = command("amneziaWG1", "dns4", "positive", None)
    assert q.verify_host(c, receipt(c))["probe"] == "dns4"
    wg = command("wireGuard","dns4","positive","wireGuardFull")
    assert q.verify_host(wg,receipt(wg))["probe"]=="dns4"
    for kind,scope,mode in [("amneziaWG1",None,"wrong-key"),("amneziaWG1",None,"wrong-psk"),("wireGuard",None,"positive"),("wireGuard","wireGuardFull","wrong-key"),("vlessReality","vlessDatagrams","positive")]:
        with pytest.raises(ValueError):
            command(kind,"dns4",mode,scope)
    view=(Path(__file__).resolve().parents[1]/"mobile/ios/App/NativeRuntimeReviewQAView.swift").read_text()
    assert 'nonce+".apl-nativeqa.test."' in view and 'probe=="dns4" && mode=="positive"' in view


@pytest.mark.parametrize("probe",("udp4","udp6","dnsWire4"))
def test_off_control_is_not_runtime_or_release_evidence(probe):
    c=q.make_command(fixture(),q.new_id(),"offControl","wireGuardFull",probe,"observe-off")
    r=receipt(c);r["probeAttempted"]=True
    out=q.verify_host(c,r)
    assert out["independent_witness_required"] and not out["runtime_authorized"] and not out["release_authorized"]
    for field,value in (("osOff",False),("probeAttempted",False),("responseSHA256","0"*64)):
        with pytest.raises(ValueError):q.verify_host(c,dict(r,**{field:value}))
    with pytest.raises(ValueError):q.validate_command(dict(c,action="run"))
    with pytest.raises(ValueError):q.validate_command(dict(c,scope=None))
    with pytest.raises(ValueError):q.validate_command(dict(c,mode="positive"))
    wrong=dict(c,reference=fixture("amneziaWG1")["reference"])
    with pytest.raises(ValueError):q.validate_command(wrong)


def test_peer_loss_requires_exact_positive_then_fresh_negative():
    from verify_nativeqa_wg_loss import verify_observation
    c=command("wireGuard","udp4","peer-loss","wireGuardFull")
    r=receipt(c);r["responseSHA256"]=q.sha(("APL_RECEIPT:"+c["nonce"]).encode())
    r["loss"]=dict(firstStart=100.,firstEnd=101.,secondStart=109.,secondEnd=113.,secondChallengeSHA256=q.sha(q.post_loss_nonce(c).encode()))
    p=dict(requestID=c["requestID"],probe="udp4",challengeSHA256=q.sha(c["nonce"].encode()),responseSHA256=r["responseSHA256"],secondChallengeSHA256=r["loss"]["secondChallengeSHA256"],localPositiveControl=True,witnessAt=100.8,cutStart=101.8,cutComplete=102.5,witnessCounts=dict(tcp4=0,tcp6=0,udp4=1,udp6=0),releaseAuthorized=False)
    o=dict(requestID=c["requestID"],probe="udp4",started=99.,ended=114.,rviRemoved=True,releaseAuthorized=False,complete=True,physicalOut=0,tunnelOut=2,ambiguous=0)
    h="100.4 (utun8, out) IP 192.0.2.1.5555 > 198.51.100.77.39883: UDP, length 48\n109.1 (utun8, out) IP 192.0.2.1.5556 > 198.51.100.77.39883: UDP, length 48\n"
    s="listening on rvi0, link-type PKTAP (Apple DLT_PKTAP)\n2 packets captured\n0 packets dropped by kernel\n"
    assert verify_observation(c,r,p,o,h,s)["postCutTunnelPackets"]==1
    for bad in (dict(p,cutComplete=110.),dict(p,witnessAt=90.),dict(p,requestID=q.new_id())):
        with pytest.raises(AssertionError):verify_observation(c,r,bad,o,h,s)
    with pytest.raises(AssertionError):verify_observation(c,r,p,o,h.replace("utun8","en0"),s)
    with pytest.raises(AssertionError):verify_observation(c,r,p,o,h.replace("109.1","105.1"),s)
    with pytest.raises(ValueError):q.verify_host(c,dict(r,loss=dict(r["loss"],secondResponseSHA256="a"*64)))
    with pytest.raises(ValueError):q.verify_host(c,dict(r,loss=dict(r["loss"],secondChallengeSHA256=q.sha(c["nonce"].encode()))))
    for kind,scope,probe in (("wireGuard",None,"udp4"),("wireGuard","wireGuardFull","tcp4"),("amneziaWG1",None,"udp4"),("vlessReality","vlessDatagrams","udp4")):
        with pytest.raises(ValueError):command(kind,probe,"peer-loss",scope)

@pytest.mark.parametrize("probe",("udp4","udp6","dnsWire4"))
def test_awg_off_control_requires_owned_full_route_and_no_response(probe):
    c=q.make_command(fixture("amneziaWG1"),q.new_id(),"offControl",None,probe,"observe-off")
    r=receipt(c);r["probeAttempted"]=True
    out=q.verify_host(c,r)
    assert out["kind"]=="amneziaWG1" and not out["runtime_authorized"] and not out["release_authorized"]
    for bad in (dict(c,scope="wireGuardFull"),dict(c,nonce="a"*40)):
        with pytest.raises(ValueError):q.validate_command(bad)
    with pytest.raises(ValueError):q.verify_host(c,dict(r,responseSHA256="0"*64))

def test_off_control_source_rejects_unexpected_exact_response_after_manager_readback():
    view=(Path(__file__).resolve().parents[1]/"mobile/ios/App/NativeRuntimeReviewQAView.swift").read_text()
    block=view.split('if command.action == .offControl {',1)[1].split('if command.action != .run',1)[0]
    assert block.index('let offResponse=await NativeRuntimeQAProbe.exchange(command)') < block.index('stage="off-control-after"') < block.index('guard offResponse==nil') < block.index('try save(')
    assert block.count('readNativeRuntimeQAManager(')==2
