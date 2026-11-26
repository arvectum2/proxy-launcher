#!/usr/bin/env python3
"""Finite independent peer shutdown after the exact first synthetic UDP reply."""
import hashlib,json,os,secrets,sys,time
from pathlib import Path
from native_runtime_qa_receipt import validate_command,post_loss_nonce,sha
from nativeqa_wg_peer import session,report,local_probe,local_dns_probe,dns_count,KINDS

def run(root,binary,client,path):
    c=json.loads(path.read_text());validate_command(c)
    assert c["mode"]=="peer-loss" and c["reference"]["kind"]=="wireGuard"
    assert root.is_dir() and root.stat().st_mode&0o077==0
    assert hashlib.sha256(binary.read_bytes()).hexdigest()==(binary.parent/"SHA256SUMS").read_text().split()[0]
    source=json.loads((root/"peer.json").read_text())
    cfg={k:source[k] for k in ("private","peer","psk")}
    assert all(len(bytes.fromhex(v))==32 for v in cfg.values())
    cfg["dual"]=True;probe=c["probe"];nonce=c["nonce"]
    pre=secrets.token_hex(20)
    dns=probe=="dns4"
    matched_probe="tcp4" if dns else probe
    if dns:
        cfg["dns"]=True
        local_dns_probe(root,binary,cfg,pre,require_exact_tcp4_marker=True)
        marker="WG_EXACT_TCP4_REPLY"
    else:
        with session(root,binary,dict(cfg,nonce=pre),"local") as (work,counts):
            local_probe(work,client,pre,[probe])
        assert all(report(work)[k]==int(k==probe) for k in KINDS)
        assert counts["c2s",1]>0 and counts["s2c",2]>0 and counts["s2c",4]>0
        marker="WG_EXACT_UDP_REPLY "+str(int(probe=="udp6"))
    with session(root,binary,dict(cfg,nonce=nonce),"physical") as (work,counts):
        print("WG_LOSS_PEER_READY",flush=True)
        deadline=time.monotonic()+55
        while marker not in (work/"server.log").read_text().splitlines():
            if time.monotonic()>=deadline:raise RuntimeError("first witness absent")
            time.sleep(.05)
        witnessAt=time.time()
        time.sleep(1)
        cutStart=time.time()
    cutComplete=time.time()
    measured=report(work)
    assert all(measured[k]==int(k==matched_probe) for k in KINDS)
    assert (work/"server.log").read_text().splitlines().count(marker)==1
    assert counts["c2s",1]>0 and counts["s2c",2]>0 and counts["s2c",4]>0
    o=dict(schema=1,requestID=c["requestID"],probe=probe,challengeSHA256=sha(nonce.encode()),
           responseSHA256=sha(("APL_RECEIPT:"+nonce).encode()),secondChallengeSHA256=sha(post_loss_nonce(c).encode()),
           localPositiveControl=True,witnessAt=witnessAt,cutStart=cutStart,cutComplete=cutComplete,
           witnessCounts={k:measured[k] for k in KINDS},releaseAuthorized=False)
    if dns:
        o["dnsAResponses"]=dns_count(work)
        assert o["dnsAResponses"]>0
    with (path.parent/"loss-peer-observation.json").open("x") as f:json.dump(o,f,sort_keys=True)
    print("WG_LOSS_PEER_STOPPED",json.dumps(o),flush=True)

if __name__=="__main__":
    os.umask(0o077)
    run(*map(Path,sys.argv[1:]))
