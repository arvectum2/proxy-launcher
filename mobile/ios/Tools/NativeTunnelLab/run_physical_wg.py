#!/usr/bin/env python3
"""Physical signed standard WG synthetic original-flow QA; no owner config."""
import argparse, base64, collections, http.server, ipaddress, json, os
import secrets, socket, subprocess, sys, tempfile, threading, time, uuid
from pathlib import Path
from run_physical_peer import APP, LAN, HOST, ctl, keypair, wait_for

RELAY,SERVER,WITNESS=39881,39882,39883

def wgkey(value):
    return base64.b64encode(base64.urlsafe_b64decode(value+"=")).decode()

def run(reference, preflight, root, kind, wrong, retain, local_only):
    private,public=map(wgkey,keypair())
    client_private,client_public=map(wgkey,keypair())
    _,wrong_public=map(wgkey,keypair())
    psk=base64.b64encode(secrets.token_bytes(32)).decode()
    nonce,pre=secrets.token_hex(20),secrets.token_hex(20)
    runid=str(uuid.uuid4())
    seen=collections.Counter()
    counts=collections.Counter()
    sizes=collections.Counter()
    witness_sizes=collections.Counter()
    lock=threading.Lock()
    stop=threading.Event()
    config={"private":base64.b64decode(private).hex(),"peer":base64.b64decode(client_public).hex(),"psk":base64.b64decode(psk).hex(),"dual":True}
    cfg=root/"server.json";cfg.write_text(json.dumps(config))
    def fixture(pub):
        return ("[Interface]\nPrivateKey = "+client_private+"\nAddress = 10.77.0.2/32, 2001:db8:77::2/128\n"
            "[Peer]\nPublicKey = "+pub+"\nPresharedKey = "+psk+"\nEndpoint = "+LAN+":39881\nAllowedIPs = 198.51.100.77/32, 2001:db8:77::77/128\n")
    class Witness(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            value=self.path.removeprefix("/")
            if value!=pre and (value!=nonce or not kind.startswith("tcp")):
                self.send_error(404);return
            with lock:seen[value]+=1
            body=("APL_RECEIPT:"+value).encode()
            self.send_response(200);self.send_header("Content-Length",str(len(body)))
            self.end_headers();self.wfile.write(body)
        def log_message(self,*args):pass
    witness=http.server.ThreadingHTTPServer((HOST,WITNESS),Witness)
    udp=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    udp.bind((HOST,WITNESS));udp.settimeout(.1)
    local=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    local.bind((HOST,RELAY));local.settimeout(.1)
    lan=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    lan.bind((LAN,RELAY));lan.settimeout(.1)
    client=[None]
    def echo():
        while not stop.is_set():
            try:data,src=udp.recvfrom(128)
            except socket.timeout:continue
            with lock:witness_sizes[len(data)]+=1
            if not kind.startswith("udp") or data!=("APL_UDP:"+nonce).encode():continue
            with lock:seen[nonce]+=1
            udp.sendto(("APL_RECEIPT:"+nonce).encode(),src)
    def inbound():
        while not stop.is_set():
            try:data,src=lan.recvfrom(65535)
            except socket.timeout:continue
            if ipaddress.ip_address(src[0]) not in ipaddress.ip_network("192.168.1.0/24"):continue
            msg=int.from_bytes(data[:4],"little")
            if msg not in (1,2,3,4):continue
            with lock:
                if sum(counts.values())>=512:continue
                if client[0] is None:client[0]=src
                if client[0]!=src:continue
                counts["in",msg]+=1
                if msg==4:sizes["in",len(data)]+=1
            local.sendto(data,(HOST,SERVER))
    def outbound():
        while not stop.is_set():
            try:data,src=local.recvfrom(65535)
            except socket.timeout:continue
            if src!=(HOST,SERVER):continue
            msg=int.from_bytes(data[:4],"little")
            if msg not in (1,2,3,4):continue
            with lock:
                target=client[0]
                if target is None:continue
                counts["out",msg]+=1
                if msg==4:sizes["out",len(data)]+=1
            lan.sendto(data,target)
    threads=[threading.Thread(target=f,daemon=True) for f in (witness.serve_forever,echo,inbound,outbound)]
    for t in threads:t.start()
    proc=None
    try:
        log=root/"server.log"
        with log.open("w") as f:proc=subprocess.Popen([str(reference),"server",str(cfg),str(SERVER)],stdout=f,stderr=subprocess.STDOUT)
        wait_for(proc,log,"PEER_QA_READY_server")
        prefile=root/"pre.conf";prefile.write_text(fixture(public))
        prelog=root/"pre.log"
        with prelog.open("w") as f:p=subprocess.Popen([str(preflight),"wg-client",str(prefile),"39879"],stdout=f,stderr=subprocess.STDOUT)
        try:
            wait_for(p,prelog,"PEER_QA_READY_wg-client")
            response=subprocess.run(["curl","--disable","--noproxy","","--silent","--max-time","8","--socks5-hostname","127.0.0.1:39879","http://198.51.100.77:39883/"+pre],capture_output=True,env={k:v for k,v in os.environ.items() if "proxy" not in k.lower()})
            good=response.returncode==0 and response.stdout==("APL_RECEIPT:"+pre).encode()
        finally:
            Path(str(prefile)+".stop").touch();p.wait(timeout=5)
        with lock:
            good=good and seen[pre]==1 and all(counts[k]>0 for k in (("in",1),("out",2),("in",4),("out",4)))
            print("WG_PHYSICAL_PREFLIGHT",good,"HANDSHAKE",counts["in",1],counts["out",2],"WITNESS",seen[pre],flush=True)
        if not good or p.returncode!=0:return 1
        if local_only:return 0
        # Fresh reference worker prevents reuse of timestamp/replay state.
        Path(str(cfg)+".stop").touch();proc.wait(timeout=6)
        if proc.returncode!=0:return 1
        Path(str(cfg)+".stop").unlink()
        with lock:client[0]=None;before=counts.copy();sizes.clear();witness_sizes.clear()
        with log.open("w") as f:proc=subprocess.Popen([str(reference),"server",str(cfg),str(SERVER)],stdout=f,stderr=subprocess.STDOUT)
        wait_for(proc,log,"PEER_QA_READY_server")
        inp=root/"native-lab-input.json"
        inp.write_text(json.dumps({"fixture":fixture(wrong_public if wrong else public),"nonce":nonce,"runID":runid,"transport":"wg-dual","probeKind":kind,"retainProfile":retain}))
        ctl("copy","to","--domain-type","appDataContainer","--domain-identifier",APP,"--source",str(inp),"--destination","Documents/native-lab-input.json")
        ctl("process","launch","--terminate-existing",APP,"--","--apl-authorized-native-qa")
        print("WG_PHYSICAL_LAUNCHED",kind,"wrong-key" if wrong else "valid",flush=True)
        result=root/"result.json"
        until=time.monotonic()+40
        while time.monotonic()<until:
            ret=ctl("copy","from","--domain-type","appDataContainer","--domain-identifier",APP,"--source","Documents/native-lab-result.json","--destination",str(result),check=False,timeout=8)
            if ret.returncode==0 and result.is_file():
                item=json.loads(result.read_text())
                if item.get("runID")==runid:
                    with lock:
                        diff=counts-before;n=seen[nonce];total=sum(seen.values())
                        print("WG_PHYSICAL_LENGTHS",sorted((d,l,c) for (d,l),c in sizes.items()),"UDP_WITNESS_LENGTHS",sorted(witness_sizes.items()),flush=True)
                    cleanup=item.get("retainedOff") is True if retain else item.get("cleaned") is True
                    expected=not wrong
                    ok=(item.get("connected") is True and item.get("receipt") is expected and n==int(expected) and total==1+int(expected) and diff["in",1]>0 and cleanup)
                    if expected:ok=ok and all(diff[k]>0 for k in (("out",2),("in",4),("out",4)))
                    else:ok=ok and diff["out",2]==0 and diff["out",4]==0
                    print("WG_PHYSICAL_RESULT",kind,"wrong-key" if wrong else "valid",json.dumps({k:item.get(k) for k in ("connected","receipt","cleaned","retainedOff","probeCode","counters")}),"WITNESS",n,"INIT",diff["in",1],"REPLY",diff["out",2],"DATA",diff["in",4],diff["out",4],"PASS" if ok else "FAIL",flush=True)
                    for marker in log.read_text().splitlines():
                        if marker.startswith("WG_PACKET_"):print(marker,flush=True)
                    return 0 if ok else 1
                result.unlink()
            time.sleep(1)
        print("WG_PHYSICAL_NO_RESULT",flush=True);return 2
    finally:
        if proc is not None and proc.poll() is None:
            Path(str(cfg)+".stop").touch()
            try:proc.wait(timeout=6)
            except subprocess.TimeoutExpired:proc.terminate();proc.wait(timeout=4)
        stop.set();witness.shutdown();witness.server_close()
        for thread in threads:thread.join(timeout=1)
        for sock in (udp,local,lan):sock.close()
        print("WG_PHYSICAL_PEER_CLEANUP",flush=True)
if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--approved",action="store_true")
    p.add_argument("--reference",type=Path,required=True);p.add_argument("--preflight",type=Path,required=True)
    p.add_argument("--kind",choices=["tcp4","tcp6","udp4","udp6"],default="tcp4")
    p.add_argument("--wrong-key",action="store_true");p.add_argument("--retain-profile",action="store_true")
    p.add_argument("--local-only",action="store_true");a=p.parse_args()
    if not a.approved:raise SystemExit(2)
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="apl-physical-wg-") as d:sys.exit(run(a.reference.resolve(),a.preflight.resolve(),Path(d),a.kind,a.wrong_key,a.retain_profile,a.local_only))
