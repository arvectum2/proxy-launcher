#!/usr/bin/env python3
"""Independent, bounded AWG peer shutdown after an exact authenticated UDP reply."""
import base64
import configparser
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time

from run_direct_witness import server, KINDS, parse_terminal
from native_runtime_qa_receipt import validate_command, post_loss_nonce, sha


def run(root, folder, binary):
    assert root.is_dir() and not root.is_symlink() and root.stat().st_mode & 0o077 == 0
    assert folder.is_dir() and not folder.is_symlink() and folder.stat().st_mode & 0o077 == 0
    assert not (folder/"loss-peer-observation.json").exists()
    c=json.loads((folder/"apl-native-runtime-qa-command.json").read_text())
    validate_command(c)
    assert c["reference"]["kind"]=="amneziaWG1" and c["mode"]=="peer-loss"
    assert c["reference"]==json.loads((root/"fixture-ref.json").read_text())["reference"]
    assert c["owner"]==(root/"owner").read_text().strip()
    expected=(binary.parent/"SHA256SUMS").read_text().split()
    assert len(expected)==2 and expected[1]==binary.name
    assert hashlib.sha256(binary.read_bytes()).hexdigest()==expected[0]
    cfg=json.loads((root/"peer.json").read_text())
    assert cfg["ClientIP"]=="192.168.1.90"
    f=configparser.ConfigParser()
    f.read(root/"fixture.txt")
    def key(section,name):
        raw=base64.b64decode(f[section][name],validate=True)
        assert len(raw)==32
        return raw.hex()
    local=dict(Private=key("Interface","PrivateKey"),Peer=key("Peer","PublicKey"),PSK=key("Peer","PresharedKey"),ClientIP="192.168.1.80")
    assert cfg["PSK"]==local["PSK"]
    # Require fresh positive control with exact keys and new peer markers.
    pre=secrets.token_hex(24);control=folder/"local-positive"
    with server(binary,control,dict(cfg,ClientIP=local["ClientIP"],Nonce=pre)):
        path=control/"client.json"
        path.write_text(json.dumps(dict(local,Nonce=pre)))
        try:
            result=subprocess.run([str(binary),"positive",str(path)],capture_output=True,timeout=25)
            assert result.returncode==0
        finally:
            path.unlink(missing_ok=True)
    log=(control/"server.log").read_text()
    counts=parse_terminal(log,0)
    assert counts[:4]==(1,1,1,1) and counts[4]>0 and counts[5]>0
    assert all(log.splitlines().count("AWG_EXACT_UDP_REPLY "+str(i))==1 for i in (0,1))
    probe=c["probe"];nonce=c["nonce"];physical=folder/"physical"
    marker="AWG_EXACT_UDP_REPLY "+str(int(probe=="udp6"))
    with server(binary,physical,dict(cfg,Nonce=nonce)):
        print("AWG_LOSS_PEER_READY",flush=True)
        deadline=time.monotonic()+55
        while marker not in (physical/"server.log").read_text().splitlines():
            if time.monotonic()>=deadline:
                raise RuntimeError("first witness absent")
            time.sleep(.05)
        witness_at=time.time()
        time.sleep(1)
        cut_start=time.time()
    cut_complete=time.time()
    log=(physical/"server.log").read_text()
    counts=parse_terminal(log,0)
    assert log.splitlines().count(marker)==1
    assert counts[:4]==tuple(int(k==probe) for k in KINDS) and counts[4]>0 and counts[5]>0
    observation=dict(schema=1,requestID=c["requestID"],probe=probe,
                     challengeSHA256=sha(nonce.encode()),responseSHA256=sha(("APL:"+nonce).encode()),
                     secondChallengeSHA256=sha(post_loss_nonce(c).encode()),localPositiveControl=True,
                     witnessAt=witness_at,cutStart=cut_start,cutComplete=cut_complete,
                     witnessCounts=dict(zip(KINDS,counts[:4])),releaseAuthorized=False)
    with (folder/"loss-peer-observation.json").open("x") as f:
        json.dump(observation,f,sort_keys=True)
    print("AWG_LOSS_PEER_STOPPED",json.dumps(observation),flush=True)


if __name__=="__main__":
    os.umask(0o077)
    run(*map(Path,sys.argv[1:]))
