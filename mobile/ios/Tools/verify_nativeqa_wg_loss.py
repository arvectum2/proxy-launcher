"""Correlate a bounded established-peer loss case, never authorize release."""
import hashlib,json,math,sys
from pathlib import Path
from native_runtime_qa_receipt import verify_host
from capture_nativeqa_rvi import target_for,summarize,limit_for

def read(p):return json.loads(p.read_text())

def verify_observation(command,receipt,peer,obs,headers,stats):
    b=verify_host(command,receipt)
    assert command["mode"]=="peer-loss"
    loss=receipt["loss"];a,z,c,d=(loss[k] for k in ("firstStart","firstEnd","secondStart","secondEnd"))
    assert peer["requestID"]==command["requestID"]==obs["requestID"]
    assert peer["probe"]==command["probe"]==obs["probe"] and peer["localPositiveControl"] is True and peer["releaseAuthorized"] is False
    assert peer["challengeSHA256"]==b["challengeSHA256"] and peer["responseSHA256"]==receipt["responseSHA256"] and peer["secondChallengeSHA256"]==loss["secondChallengeSHA256"]
    dns=command["probe"]=="dns4"
    matched_probe="tcp4" if dns else command["probe"]
    assert peer["witnessCounts"]=={k:int(k==matched_probe) for k in ("tcp4","tcp6","udp4","udp6")}
    if dns:
        assert type(peer.get("dnsAResponses")) is int and 0<peer["dnsAResponses"]<=4096
    else:
        assert "dnsAResponses" not in peer
    w,cs,ce=(peer[k] for k in ("witnessAt","cutStart","cutComplete"))
    assert all(type(t) in (int,float) and math.isfinite(t) for t in (w,cs,ce))
    assert a-.5<=w<=z+.5 and w<=cs<=ce and z<=ce and ce+.5<c
    assert obs["started"]<a and d<obs["ended"] and obs["rviRemoved"] is True and obs["releaseAuthorized"] is False
    counts=summarize(headers,stats,target_for(command),obs["started"],obs["ended"],limit=limit_for(command))
    assert counts["complete"] and counts["physicalOut"]==0 and counts["tunnelOut"]>=2
    assert all(obs[k]==v for k,v in counts.items())
    stamps=[float(row.split()[0]) for row in headers.splitlines() if row.strip()]
    before=[t for t in stamps if a-.5<=t<=z+.5 and t<cs]
    after=[t for t in stamps if c-.5<=t<=d+.5 and t>ce]
    assert before and after and len(before)+len(after)==len(stamps)
    return dict(firstTunnelPackets=len(before),postCutTunnelPackets=len(after),physicalOut=0,releaseAuthorized=False)

def verify_dir(folder):
    cp=folder/"apl-native-runtime-qa-command.json";cmd=read(cp)
    obs=read(folder/"rvi-observation.json")
    assert obs["commandSHA256"]==hashlib.sha256(cp.read_bytes()).hexdigest()
    return verify_observation(cmd,read(folder/"receipt.json"),read(folder/"loss-peer-observation.json"),obs,(folder/"headers.txt").read_text(),(folder/"capture-stats.txt").read_text())

if __name__=="__main__":
    print(json.dumps(verify_dir(Path(sys.argv[1])),sort_keys=True))
