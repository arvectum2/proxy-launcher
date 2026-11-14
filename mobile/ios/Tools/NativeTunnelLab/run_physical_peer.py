#!/usr/bin/env python3
"""Explicitly authorized isolated iPhone QA. Never copies owner data."""
import argparse, ipaddress, http.server, json, os, secrets, select, socket
import socketserver, subprocess, sys, tempfile, threading, time, uuid
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from run_xray_vless_peer_qa import keypair, wait_for

DEVICE="00008110-001C51810A12401E"
APP="ru.arvectum.proxylauncher.lab.nativeqa"
LAN="192.168.1.80"
HOST="127.0.0.1"
def ctl(*args, check=True, timeout=15):
    return subprocess.run(["xcrun","devicectl","device",*args[:2],"--device",DEVICE,*args[2:]],
            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=check,timeout=timeout)
def cleanup_only(root):
    runid=str(uuid.uuid4())
    fixture=root/"native-lab-input.json"
    fixture.write_text(json.dumps({"fixture":"cleanup-only","nonce":"0"*40,"runID":runid}))
    ctl("copy","to","--domain-type","appDataContainer","--domain-identifier",APP,
        "--source",str(fixture),"--destination","Documents/native-lab-input.json")
    ctl("process","launch","--terminate-existing",APP,"--","--apl-authorized-native-qa")
    resultpath=root/"cleanup-result.json"
    until=time.monotonic()+20
    while time.monotonic()<until:
        ret=ctl("copy","from","--domain-type","appDataContainer","--domain-identifier",APP,
                "--source","Documents/native-lab-result.json","--destination",str(resultpath),check=False,timeout=8)
        if ret.returncode==0 and resultpath.is_file():
            item=json.loads(resultpath.read_text())
            if item.get("runID")==runid:
                safe=item.get("cleaned") is True and item.get("connected") is False
                print("PHYSICAL_QA_CLEANUP_CONFIRMED",safe,flush=True)
                return 0 if safe else 1
            resultpath.unlink()
        time.sleep(1)
    print("PHYSICAL_QA_CLEANUP_UNCONFIRMED",flush=True)
    return 2


def run(peer, root):
    private,public=keypair(); uid=str(uuid.uuid4());sid=secrets.token_hex(8)
    nonce=secrets.token_hex(20);runid=str(uuid.uuid4())
    seen=[];lock=threading.Lock();stop=threading.Event();accepted=0; directions=[0,0]
    class Witness(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/"+nonce: self.send_error(404);return
            with lock:seen.append(1)
            body=("APL_RECEIPT:"+nonce).encode()
            self.send_response(200);self.send_header("Content-Length",str(len(body)))
            self.end_headers();self.wfile.write(body)
        def log_message(self,*a):pass
    # Bounded TCP relay only from fixed LAN address to fixed authenticated peer.
    # No general forwarding or non-LAN listener.
    class Relay(socketserver.BaseRequestHandler):
        def handle(self):
            self.request.settimeout(5)
            try:
                with socket.create_connection((HOST,39882),timeout=3) as upstream:
                    until=time.monotonic()+18
                    while not stop.is_set() and time.monotonic()<until:
                        ready,_,_=select.select([self.request,upstream],[],[],.2)
                        for src in ready:
                            data=src.recv(65536)
                            if not data:return
                            with lock: directions[0 if src is self.request else 1]+=len(data)
                            (upstream if src is self.request else self.request).sendall(data)
            except OSError:return
    class Server(socketserver.ThreadingTCPServer):
        daemon_threads=True
        allow_reuse_address=True
        def verify_request(self,request,address):
            nonlocal accepted
            # This local test listener accepts only this specific LAN subnet.
            if ipaddress.ip_address(address[0]) not in ipaddress.ip_network("192.168.1.0/24"):
                return False
            with lock:
                if accepted >= 12: return False
                accepted+=1
            return not stop.is_set()
    config={"log":{"loglevel":"none"},"inbounds":[{"tag":"qa-in","listen":HOST,"port":39882,
      "protocol":"vless","settings":{"clients":[{"id":uid}],"decryption":"none"},
      "streamSettings":{"network":"raw","security":"reality","realitySettings":{
      "target":HOST+":39884","serverNames":["example.com"],"privateKey":private,"shortIds":[sid]}}}],
      "outbounds":[{"tag":"deny","protocol":"blackhole"},{"tag":"receipt-only","protocol":"freedom","settings":{
      "redirect":HOST+":39883","finalRules":[{"action":"allow","network":"tcp","port":"39883","ip":[HOST+"/32"]},{"action":"block"}]}}],
      "routing":{"domainStrategy":"AsIs","rules":[{"type":"field","inboundTag":["qa-in"],
      "ip":["198.51.100.77/32"],"port":"39883","network":"tcp","outboundTag":"receipt-only"}]}}
    conf=root/"peer.json";conf.write_text(json.dumps(config))
    fixture=root/"native-lab-input.json"
    fixture.write_text(json.dumps({"fixture":f"vless://{uid}@{LAN}:39882?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk={public}&sid={sid}","nonce":nonce,"runID":runid}))
    cert=root/"tls.crt";key=root/"tls.key"
    subprocess.run(["openssl","req","-x509","-newkey","rsa:2048","-nodes","-keyout",str(key),"-out",str(cert),"-days","1","-subj","/CN=example.com"],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    witness=http.server.ThreadingHTTPServer((HOST,39883),Witness)
    relay=Server((LAN,39882),Relay)
    for server in (witness,relay):threading.Thread(target=server.serve_forever,daemon=True).start()
    decoy=subprocess.Popen(["openssl","s_server","-accept",HOST+":39884","-cert",str(cert),"-key",str(key),"-tls1_3","-quiet"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    log=root/"server.log"
    with log.open("w") as f: process=subprocess.Popen([str(peer),"server",str(conf),"39882"],stdout=f,stderr=subprocess.STDOUT)
    try:
        wait_for(process,log,"PEER_QA_READY_server")
        ctl("copy","to","--domain-type","appDataContainer","--domain-identifier",APP,"--source",str(fixture),"--destination","Documents/native-lab-input.json")
        ctl("process","launch","--terminate-existing",APP,"--","--apl-authorized-native-qa")
        print("PHYSICAL_QA_LAUNCH_REQUESTED",flush=True)
        resultpath=root/"result.json"
        until=time.monotonic()+45
        while time.monotonic()<until:
            ret=ctl("copy","from","--domain-type","appDataContainer","--domain-identifier",APP,"--source","Documents/native-lab-result.json","--destination",str(resultpath),check=False,timeout=8)
            if ret.returncode==0 and resultpath.is_file():
                result=json.loads(resultpath.read_text())
                if result.get("runID")==runid:
                    with lock:n=len(seen); print("PHYSICAL_QA_RELAY",accepted,directions,flush=True)
                    print("PHYSICAL_QA_RESULT",json.dumps({k:result.get(k) for k in ("connected","receipt","cleaned","probeCode","counters")}),"WITNESS",n,flush=True)
                    return 0 if result["connected"] and result["receipt"] and result["cleaned"] and n==1 else 1
                resultpath.unlink()
            time.sleep(2)
        progress=root/"progress.json"
        ret=ctl("copy","from","--domain-type","appDataContainer","--domain-identifier",APP,
                "--source","Documents/native-lab-progress.json","--destination",str(progress),check=False,timeout=8)
        if ret.returncode==0 and progress.is_file():
            item=json.loads(progress.read_text())
            if item.get("runID")==runid:
                print("PHYSICAL_QA_LAST_STAGE",item.get("stage"),flush=True)
        print("PHYSICAL_QA_NO_RESULT",flush=True);return 2
    finally:
        stop.set()
        Path(str(conf)+".stop").touch()
        try:process.wait(timeout=5)
        except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=5)
        decoy.terminate();decoy.wait(timeout=5)
        for server in (relay,witness):server.shutdown();server.server_close()
        print("PHYSICAL_QA_PEER_CLEANUP",flush=True)
if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--approved",action="store_true");p.add_argument("--peer",type=Path);p.add_argument("--cleanup-only",action="store_true");a=p.parse_args()
    if not a.approved or (not a.cleanup_only and a.peer is None):raise SystemExit(2)
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="apl-physical-native-fixture-") as d:
        sys.exit(cleanup_only(Path(d)) if a.cleanup_only else run(a.peer.resolve(),Path(d)))
