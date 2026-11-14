#!/usr/bin/env python3
"""Local-only native WG lab with independent UDP header and HTTP receipts."""
import argparse
import base64
import http.server
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import threading
from collections import Counter
from run_xray_vless_peer_qa import keypair, wait_for, check_port_free

HOST = "127.0.0.1"
RELAY, SERVER, WITNESS, CLIENT = 39881,39882,39883,39879
TARGET = "198.51.100.77"

def wgkey(raw):
    return base64.b64encode(base64.urlsafe_b64decode(raw+"=")).decode()

def run(sim,binary,host_server,root,reference=False,dual=False):
    for port in (SERVER,WITNESS,CLIENT):
        check_port_free(port)
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as check:
        check.bind((HOST,SERVER))
    private,public=map(wgkey,keypair())
    client_private,client_public=map(wgkey,keypair())
    _,wrong_public=map(wgkey,keypair())
    psk=base64.b64encode(secrets.token_bytes(32)).decode()
    bad_psk=base64.b64encode(secrets.token_bytes(32)).decode()
    cases=[(n,"/"+secrets.token_hex(20)) for n in ("valid","bad_key","bad_psk","stopped")]
    if dual:
        cases=[(name, ["/"+secrets.token_hex(20) for _ in range(3)]) for name,_ in cases]
    seen=[]
    udp_seen=[]
    http_paths={paths[2] for _,paths in cases} if dual else set(dict(cases).values())
    udp_paths={path for _,paths in cases for path in paths[:2]} if dual else set()
    counts=Counter()
    lock=threading.Lock()
    stop=threading.Event()

    class Witness(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in http_paths:
                self.send_error(404)
                return
            with lock:
                seen.append(self.path)
            body=("APL_RECEIPT:"+self.path[1:]).encode()
            self.send_response(200)
            self.send_header("Content-Length",str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def log_message(self,*_):
            pass

    relay=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    relay.bind((HOST,RELAY))
    relay.settimeout(.1)
    def forward():
        client=None
        while not stop.is_set():
            try:
                data,src=relay.recvfrom(65535)
            except socket.timeout:
                continue
            if src[0]!=HOST:
                continue
            direction="s2c" if src[1]==SERVER else "c2s"
            kind=int.from_bytes(data[:4],"little") if len(data)>=4 else 0
            if kind not in (1,2,3,4):
                continue
            with lock:
                counts[direction,kind]+=1
            if direction=="c2s":
                client=src
                relay.sendto(data,(HOST,SERVER))
            elif client:
                relay.sendto(data,client)

    server={
        "log":{"loglevel":"none"},
        "inbounds":[{"tag":"wg-in","listen":HOST,"port":SERVER,"protocol":"wireguard",
          "settings":{"secretKey":private,"address":["10.77.0.1/32"],"noKernelTun":True,
             "mtu":1280,"peers":[{"publicKey":client_public,"preSharedKey":psk,
             "allowedIPs":["10.77.0.2/32"],"email":"lab"}]}}],
        "outbounds":[{"tag":"deny","protocol":"blackhole"},{"tag":"receipt","protocol":"freedom",
          "settings":{"redirect":f"{HOST}:{WITNESS}","finalRules":[
           {"action":"allow","network":"tcp","port":str(WITNESS),"ip":["127.0.0.1/32"]},
           {"action":"block"}]}}],
        "routing":{"domainStrategy":"AsIs","rules":[{"type":"field","inboundTag":["wg-in"],
          "ip":[TARGET+"/32"],"port":str(WITNESS),"network":"tcp","outboundTag":"receipt"}]}
    }
    if reference:
        # Separate official wireguard-go peer accepts the same ephemeral keys.
        server = {"private":base64.b64decode(private).hex(),
                  "peer":base64.b64decode(client_public).hex(),
                  "psk":base64.b64decode(psk).hex()}
    if dual:
        if not reference: raise ValueError("dual requires reference")
        server["dual"]=True
    cfg=root/"server.json"
    cfg.write_text(json.dumps(server))
    witness=http.server.ThreadingHTTPServer((HOST,WITNESS),Witness)
    worker=threading.Thread(target=witness.serve_forever,daemon=True)
    udp=threading.Thread(target=forward,daemon=True)
    worker.start()
    udp.start()
    udp_witness=None
    if dual:
        udp_witness=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        udp_witness.bind((HOST,WITNESS))
        udp_witness.settimeout(.1)
        def echo():
            while not stop.is_set():
                try:
                    data,src=udp_witness.recvfrom(128)
                except socket.timeout:
                    continue
                if len(data)!=48 or not data.startswith(b"APL_UDP:"):
                    continue
                path="/"+data[8:].decode("ascii",errors="replace")
                if path not in udp_paths:
                    continue
                with lock:
                    udp_seen.append(path)
                udp_witness.sendto(b"APL_RECEIPT:"+data[8:],src)
        echo_thread=threading.Thread(target=echo,daemon=True)
        echo_thread.start()
    proc=None
    try:
        log=root/"server.log"
        with log.open("w") as f:
            proc=subprocess.Popen([str(host_server),"server",str(cfg),str(SERVER)],stdout=f,stderr=subprocess.STDOUT)
        wait_for(proc,log,"PEER_QA_READY_server")
        def stop_server():
            Path(str(cfg)+".stop").touch()
            proc.wait(timeout=5)
            if proc.returncode!=0 or "PEER_QA_STOPPED_server" not in log.read_text():
                raise RuntimeError("WG peer did not stop")
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as check:
                check.bind((HOST,SERVER))
        for name,path in cases:
            if name=="stopped":
                stop_server()
            fixture=root/(name+".conf")
            fixture.write_text("[Interface]\nPrivateKey = "+client_private+"\nAddress = 10.77.0.2/32\n"
                "[Peer]\nPublicKey = "+(wrong_public if name=="bad_key" else public)+
                "\nPresharedKey = "+(bad_psk if name=="bad_psk" else psk)+
                f"\nEndpoint = {HOST}:{RELAY}\nAllowedIPs = {TARGET}/32\n")
            if dual:
                text=fixture.read_text().replace("Address = 10.77.0.2/32","Address = 10.77.0.2/32, 2001:db8:77::2/128")
                text=text.replace(f"AllowedIPs = {TARGET}/32",f"AllowedIPs = {TARGET}/32, 2001:db8:77::77/128")
                fixture.write_text(text)
            Path(str(fixture)+".path").write_text("\n".join(path) if dual else path)
            with lock:
                before=counts.copy()
            result=subprocess.run(["xcrun","simctl","spawn",sim,str(binary),"wg-dual" if dual else "wg-tun",str(fixture),str(CLIENT)],
                stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=40 if dual else 25)
            markers=[line for line in result.stdout.splitlines() if line.startswith(("TUN_QA_","PEER_QA_"))]
            if dual:
                expected=name=="valid"
                with lock:
                    received=[udp_seen.count(path[0]),udp_seen.count(path[1]),seen.count(path[2])]
                    diff=counts-before
                correct=all(markers.count("TUN_QA_DUAL_"+kind+"_"+str(expected).lower())==1 for kind in ("udp4","udp6","tcp6"))
                lifecycle=(markers.count("TUN_QA_RUST_EXIT_0")==3 and
                    markers.count("TUN_QA_RUST_DRAINED_DESCRIPTOR_CLOSED")==3 and
                    markers.count("TUN_QA_XRAY_STOP_COMPLETE")==3 and
                    "PEER_QA_STOPPED_wg-dual" in markers and
                    "TUN_QA_UDP_INJECTED_4" in markers and "TUN_QA_UDP_INJECTED_6" in markers and
                    "TUN_QA_SYNACK" in markers)
                print(f"WG_DUAL_{name}_RC_{result.returncode}_WITNESS_{received}_INIT_{diff['c2s',1]}_REPLY_{diff['s2c',2]}_DATA_{diff['c2s',4]}/{diff['s2c',4]}",flush=True)
                if result.returncode!=0 or not correct or not lifecycle or received!=[int(expected)]*3 or diff["c2s",1]<1 or (expected and not all(diff[k] for k in (("s2c",2),("c2s",4),("s2c",4)))):
                    print("\n".join(markers),flush=True)
                    raise RuntimeError("WG dual acceptance failed: "+name)
                continue
            expected=name=="valid"
            ok="TUN_QA_RECEIPT_true" in markers
            with lock:
                diff=counts-before
                count=seen.count(path)
            print(f"WG_CASE_{name}_RC_{result.returncode}_RECEIPT_{ok}_WITNESS_{count}_INIT_{diff['c2s',1]}_REPLY_{diff['s2c',2]}_DATA_IN_{diff['c2s',4]}_DATA_OUT_{diff['s2c',4]}",flush=True)
            if (result.returncode!=0 or not all(m in markers for m in ("TUN_QA_SYNACK","TUN_QA_RUST_EXIT_0","TUN_QA_RUST_DRAINED_DESCRIPTOR_CLOSED","PEER_QA_STOPPED_wg-tun"))
                or ok!=expected or count!=int(expected) or diff["c2s",1]<1
                or (expected and not all(diff[k] for k in (("s2c",2),("c2s",4),("s2c",4))))):
                print("\n".join(markers),flush=True)
                raise RuntimeError("WG acceptance failed: "+name)
        if dual:
            if sorted(udp_seen)!=sorted(cases[0][1][:2]) or seen!=[cases[0][1][2]]:
                raise RuntimeError("unexpected dual witness receipts")
            print("APL_WG_REFERENCE_DUAL_APP_UDP4_UDP6_TCP6_12_PROBES_PASS",flush=True)
            return
        if seen!=[cases[0][1]]:
            raise RuntimeError("Unexpected witness receipts")
        print(("APL_WG_REFERENCE" if reference else "APL_WG_REAL") + "_UDP_HANDSHAKE_TUN_4_CASES_PASS",flush=True)
    finally:
        if proc is not None and proc.poll() is None:
            Path(str(cfg)+".stop").touch()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.terminate()
                proc.wait(timeout=4)
        stop.set()
        udp.join(timeout=1)
        relay.close()
        if udp_witness is not None:
            echo_thread.join(timeout=1)
            udp_witness.close()
        witness.shutdown()
        witness.server_close()
        worker.join(timeout=1)

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator",required=True)
    parser.add_argument("--binary",required=True,type=Path)
    parser.add_argument("--host-server",required=True,type=Path)
    parser.add_argument("--reference",action="store_true")
    parser.add_argument("--dual",action="store_true")
    args=parser.parse_args()
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="apl-xray-wg-") as tmp:
        run(args.simulator,args.binary.resolve(),args.host_server.resolve(),Path(tmp),reference=args.reference,dual=args.dual)
