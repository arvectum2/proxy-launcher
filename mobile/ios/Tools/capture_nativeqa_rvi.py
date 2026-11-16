#!/usr/bin/env python3
"""Bounded header-only synthetic native QA observation. Never release authority."""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import time

from native_runtime_qa_receipt import validate_command

TARGETS = {
    "udp4": ("198.51.100.77", 39883),
    "udp6": ("2001:db8:77::77", 39883),
    "dnsWire4": ("192.0.2.53", 53),
    "dns4": ("192.0.2.53", 53),
}
RVI = "/Library/Apple/usr/bin/rvictl"
TCPDUMP = "/usr/sbin/tcpdump"
LIMIT = 30

def target_for(command):
    validate_command(command)
    if command["reference"]["kind"] != "wireGuard" or command.get("scope") != "wireGuardFull" or command["action"] not in ("offControl", "run"):
        raise ValueError("unsupported RVI observation")
    return TARGETS[command["probe"]]

def summarize(headers, stats, target, started, ended):
    # PKTAP exposes the device interface and direction. Ambiguous rows or
    # missing metadata never become proof of non-escape.
    counts = {"physicalOut":0,"tunnelOut":0,"ambiguous":0}
    for line in headers.splitlines():
        if not line.strip():continue
        match = re.fullmatch(r"(\d+\.\d+) \(([A-Za-z0-9_]+), (in|out)\) IP6? \S+ > (\S+)\.(\d+): UDP, length (\d+)",line.strip())
        if not match:
            counts["ambiguous"]+=1
            continue
        stamp,iface,direction,address,port,length=match.groups()
        try:
            exact=ipaddress.ip_address(address)==ipaddress.ip_address(target[0]) and int(port)==target[1]
        except ValueError:exact=False
        if not exact or not started<=float(stamp)<=ended or direction!="out":
            counts["ambiguous"]+=1
        elif re.fullmatch(r"(?:en|pdp_ip)\d+",iface):
            counts["physicalOut"]+=1
        elif re.fullmatch(r"utun\d+",iface):
            counts["tunnelOut"]+=1
        else:counts["ambiguous"]+=1
    captured=re.findall(r"(?m)^(\d+) packets? captured$",stats)
    dropped=re.findall(r"(?m)^(\d+) packets? dropped by kernel$",stats)
    complete=(len(captured)==len(dropped)==1 and int(dropped[0])==0
              and int(captured[0])==sum(counts.values())<LIMIT and counts["ambiguous"]==0
              and "link-type PKTAP" in stats)
    return dict(counts,complete=complete)

def capture(folder,device):
    if not re.fullmatch(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}",device):
        raise ValueError("invalid device ID")
    if not folder.is_dir() or folder.is_symlink() or folder.stat().st_mode & 0o077:
        raise ValueError("private evidence directory required")
    command_path=folder/"apl-native-runtime-qa-command.json"
    command=json.loads(command_path.read_text())
    address,port=target_for(command)
    if any((folder/name).exists() for name in ("headers.txt","capture-stats.txt","capture-stop","rvi-observation.json")):
        raise ValueError("capture must use fresh evidence directory")
    def interfaces():
        return set(subprocess.check_output(["/sbin/ifconfig","-l"],text=True).split())
    before=interfaces()
    if any(x.startswith("rvi") for x in before):
        raise ValueError("existing RVI must not be interrupted")
    p=None;started=ended=0
    subprocess.run(["sudo","-n",RVI,"-s",device],check=True,timeout=12)
    try:
        names=interfaces()-before
        if len(names)!=1 or not re.fullmatch(r"rvi\d+",next(iter(names))):
            raise RuntimeError("unexpected new interface")
        interface=next(iter(names))
        with (folder/"headers.txt").open("x") as out,(folder/"capture-stats.txt").open("x") as err:
            started=time.time()
            p=subprocess.Popen(["sudo","-n",TCPDUMP,"-i",interface,"-y","PKTAP","-p","-k","ID","-nn","-q","-tt","-l","-s","256","-c",str(LIMIT),f"udp and dst host {address} and dst port {port}"],stdout=out,stderr=err)
            deadline=time.monotonic()+8
            while "listening on" not in (folder/"capture-stats.txt").read_text():
                if p.poll() is not None or time.monotonic()>=deadline:raise RuntimeError("capture not ready")
                time.sleep(.2)
            print("RVI_FILTER_READY",flush=True)
            deadline=time.monotonic()+65
            while p.poll() is None and time.monotonic()<deadline and not (folder/"capture-stop").exists():time.sleep(.2)
    finally:
        try:
            if p is not None and p.poll() is None:
                subprocess.run(["sudo","-n","/bin/kill","-INT",str(p.pid)],check=False,timeout=5)
                try:p.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    subprocess.run(["sudo","-n","/bin/kill","-TERM",str(p.pid)],check=False,timeout=5)
                    p.wait(timeout=5)
            ended=time.time()
        finally:
            subprocess.run(["sudo","-n",RVI,"-x",device],check=True,timeout=12)
            if any(x.startswith("rvi") for x in interfaces()):raise RuntimeError("RVI cleanup incomplete")
    summary=summarize((folder/"headers.txt").read_text(),(folder/"capture-stats.txt").read_text(),(address,port),started,ended)
    summary.update(requestID=command["requestID"],commandSHA256=hashlib.sha256(command_path.read_bytes()).hexdigest(),probe=command["probe"],started=started,ended=ended,rviRemoved=True,releaseAuthorized=False)
    with (folder/"rvi-observation.json").open("x") as f:json.dump(summary,f,sort_keys=True)
    print("RVI_OBSERVATION",json.dumps(summary,sort_keys=True),flush=True)

if __name__=="__main__":
    os.umask(0o077)
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder",type=Path);parser.add_argument("device")
    args=parser.parse_args()
    capture(args.folder,args.device)
