#!/usr/bin/env python3
"""Finite synthetic WireGuard witness using pinned independent wireguard-go."""
import argparse
from collections import Counter
from contextlib import contextmanager
import hashlib, ipaddress, json, os, secrets, select, socket, subprocess, threading, time, uuid
from pathlib import Path
from native_runtime_qa_receipt import validate_command
from nativeqa_vless_tcp4_peer import socks_udp_probe
from run_xray_vless_peer_qa import wait_for
from unified_synthetic_fixture import keypair, b64
import re

LAN, HOST, PORT, BACKEND = "192.168.1.80", "127.0.0.1", 39881, 39882
KINDS=("tcp4","tcp6","udp4","udp6")
SUBNET=ipaddress.ip_network("192.168.1.0/24")


def packet_kind(data):
    if len(data)<4:return None
    kind=int.from_bytes(data[:4],"little")
    if kind in (1,2,3):return kind if len(data)=={1:148,2:92,3:64}[kind] else None
    return 4 if kind==4 and 32<=len(data)<=2048 and len(data)%16==0 else None


@contextmanager
def session(root, binary, cfg, phase):
    assert phase in ("local","physical")
    work=root/("wg-witness-"+str(uuid.uuid4()))
    work.mkdir(mode=0o700)
    path=work/"server.json";path.write_text(json.dumps(cfg))
    log=work/"server.log"
    stop=threading.Event();counts=Counter();errors=[]
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as lan, socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as local:
        lan.bind((LAN,PORT));local.bind((HOST,PORT))
        def relay():
            client=None
            try:
                while not stop.is_set():
                    ready,_,_=select.select([lan,local],[],[],.1)
                    for incoming in ready:
                        data,src=incoming.recvfrom(4096)
                        kind=packet_kind(data)
                        if not kind:continue
                        if incoming is lan:
                            ip=ipaddress.ip_address(src[0])
                            if ip not in SUBNET or (phase=="local")!=(src[0]==LAN):continue
                            if client is None and kind==1:client=src
                            if client!=src:continue
                            direction="c2s";dest=(HOST,BACKEND);out=local
                        elif src==(HOST,BACKEND) and client:
                            direction="s2c";dest=client;out=lan
                        else:continue
                        if sum(counts.values())>=512:continue
                        counts[direction,kind]+=1
                        out.sendto(data,dest)
            except OSError as err:
                if not stop.is_set():errors.append(type(err).__name__)
        worker=threading.Thread(target=relay,daemon=True);worker.start()
        with log.open("w") as stream:p=subprocess.Popen([str(binary),"server",str(path),str(BACKEND)],stdout=stream,stderr=subprocess.STDOUT)
        try:
            wait_for(p,log,"PEER_QA_READY_server")
            yield work,counts
        finally:
            Path(str(path)+".stop").touch()
            try:p.wait(timeout=12)
            except subprocess.TimeoutExpired:
                p.terminate();p.wait(timeout=5)
            stop.set();worker.join(timeout=2)
            assert not worker.is_alive() and not errors and p.returncode==0,"WG peer cleanup failed"


def report(work):
    lines=[l for l in (work/"server.log").read_text().splitlines() if l.startswith("WG_WITNESS ")]
    assert len(lines)==1
    return {key:int(value) for key,value in (s.split("=") for s in lines[0].split()[1:])}


def local_probe(root, binary, nonce, probes, fixture=None, expected=True):
    marker=root/"client.conf"
    marker.write_text(fixture if fixture is not None else (root.parent/"fixture.txt").read_text())
    log=root/"client.log"
    with log.open("w") as out:p=subprocess.Popen([str(binary),"wg-client",str(marker),"39879"],stdout=out,stderr=subprocess.STDOUT)
    try:
        wait_for(p,log,"PEER_QA_READY_wg-client")
        for probe in probes:
            target="198.51.100.77" if probe.endswith("4") else "2001:db8:77::77"
            if probe.startswith("udp"):
                ok=socks_udp_probe(target,nonce)
            else:
                authority=target if probe.endswith("4") else "["+target+"]"
                got=subprocess.run(["curl","--disable","--noproxy","","--silent","--max-time","5","--socks5-hostname",HOST+":39879","http://"+authority+":39883/"+nonce],capture_output=True,env={k:v for k,v in os.environ.items() if "proxy" not in k.lower()})
                ok=got.returncode==0 and got.stdout==("APL_RECEIPT:"+nonce).encode()
            assert ok==expected,"local WG "+probe+" mismatch"
    finally:
        Path(str(marker)+".stop").touch()
        p.wait(timeout=7)
    assert p.returncode==0


def run(root,binary,client,command,preflight_only):
    assert root.is_dir() and root.stat().st_mode & 0o077 == 0
    source=json.loads((root/"peer.json").read_text())
    cfg={k:source[k] for k in ("private","peer","psk")}
    assert all(isinstance(v,str) and len(bytes.fromhex(v))==32 for v in cfg.values())
    cfg["dual"]=True
    probe=None;item=None
    if command:
        item=json.loads(command.read_text())
        validate_command(item)
        assert item["action"]=="run" and item["reference"]["kind"]=="wireGuard" and item["mode"] in ("positive","wrong-key")
        probe=item["probe"]
    negative=item is not None and item["mode"]=="wrong-key"
    original=(root/"fixture.txt").read_text()
    matching=original
    if negative:
        private,public=keypair()
        cfg["private"]=private.hex()
        pattern=r"(?m)^PublicKey = [A-Za-z0-9+/]{43}=$"
        assert len(re.findall(pattern,original))==1
        matching=re.sub(pattern,"PublicKey = "+b64(public),original)
        assert matching!=original
    pre=secrets.token_hex(20);probes=[probe] if probe else KINDS
    with session(root,binary,dict(cfg,nonce=pre),"local") as (work,counts):
        local_probe(work,client,pre,probes,matching)
    local=report(work)
    assert all(local[p]==(1 if p in probes else 0) for p in KINDS) and counts["c2s",1]>0 and counts["s2c",2]>0
    if negative:
        with session(root,binary,dict(cfg,nonce=pre),"local") as (work,failed):
            local_probe(work,client,pre,probes,original,False)
        assert all(report(work)[p]==0 for p in KINDS) and failed["c2s",1]>0 and failed["s2c",2]==0
    print("NATIVELAB_WG_PREFLIGHT_PASS",",".join(probes),flush=True)
    if preflight_only or item is None:return 0
    nonce=item["nonce"]
    with session(root,binary,dict(cfg,nonce=nonce),"physical") as (work,counts):
        print("NATIVELAB_WG_PEER_READY",flush=True)
        deadline=time.monotonic()+100
        while time.monotonic()<deadline and not (root/("stop-"+item["requestID"])).exists():time.sleep(.1)
    witness=report(work)
    result={"schema":1,"requestID":item["requestID"],"mode":item["mode"],"probe":probe,"challengeSHA256":hashlib.sha256(nonce.encode()).hexdigest(),"localPositiveControl":True,"localNegativeControl":negative,"witnessCounts":{p:witness[p] for p in KINDS},"relayCounts":{d+str(k):counts[d,k] for d in ("c2s","s2c") for k in range(1,5)},"responseSHA256":hashlib.sha256(("APL_RECEIPT:"+nonce).encode()).hexdigest() if witness[probe]==1 else None,"release_authorized":False}
    (work/"peer-observation.json").write_text(json.dumps(result,sort_keys=True)+"\n")
    print("NATIVELAB_WG_PEER_OBSERVATION",json.dumps(result),flush=True)
    if negative:
        return 0 if all(witness[p]==0 for p in KINDS) and counts["c2s",1]>0 and counts["s2c",2]==0 and counts["s2c",4]==0 else 2
    return 0 if all(witness[p]==(1 if p==probe else 0) for p in KINDS) and counts["c2s",1]>0 and counts["s2c",2]>0 and counts["c2s",4]>0 and counts["s2c",4]>0 else 2


if __name__=="__main__":
    os.umask(0o077)
    p=argparse.ArgumentParser(description=__doc__)
    for k in ("root","reference_peer","client_peer"):p.add_argument(k,type=Path)
    p.add_argument("--command",type=Path);p.add_argument("--preflight-only",action="store_true")
    a=p.parse_args()
    raise SystemExit(run(a.root,a.reference_peer,a.client_peer,a.command,a.preflight_only))
