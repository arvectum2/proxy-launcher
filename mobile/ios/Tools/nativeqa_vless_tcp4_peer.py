#!/usr/bin/env python3
"""Finite private-LAN witness, one synthetic VLESS target and transport only."""
import argparse, hashlib, http.server, ipaddress, json, os
from pathlib import Path
import secrets, select, socket, socketserver, ssl, subprocess
import threading, time, uuid
from native_runtime_qa_receipt import validate_command
from run_xray_vless_peer_qa import wait_for
from unified_synthetic_fixture import keypair, url64
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

LAN, HOST, TARGET, PORT = "192.168.1.80", "127.0.0.1", "198.51.100.77", 39882


def config(root, probe="tcp4"):
    assert probe in ("tcp4","tcp6","udp4","udp6")
    target=TARGET if probe.endswith("4") else "2001:db8:77::77"
    network=probe[:3]
    # Use only the ephemeral keys from the private fixture, not arbitrary routing.
    i=json.loads((root/"peer.json").read_text())["inbounds"][0]
    uid=i["settings"]["clients"][0]["id"]
    reality=i["streamSettings"]["realitySettings"]
    key,sid=reality["privateKey"],reality["shortIds"][0]
    assert str(uuid.UUID(uid))==uid
    import base64,re
    assert re.fullmatch(r"[A-Za-z0-9_-]{43}",key) and len(base64.urlsafe_b64decode(key+"="))==32
    assert re.fullmatch(r"[a-f0-9]{16}",sid)
    return {"log":{"loglevel":"none"},"inbounds":[{"tag":"qa-in","listen":HOST,"port":PORT,"protocol":"vless","settings":{"clients":[{"id":uid}],"decryption":"none"},"streamSettings":{"network":"raw","security":"reality","realitySettings":{"target":HOST+":39884","serverNames":["example.com"],"privateKey":key,"shortIds":[sid]}}}],"outbounds":[{"tag":"deny","protocol":"blackhole"},{"tag":"receipt-only","protocol":"freedom","settings":{"redirect":HOST+":39883","finalRules":[{"action":"allow","network":network,"port":"39883","ip":[HOST+"/32"]},{"action":"block"}]}}],"routing":{"domainStrategy":"AsIs","rules":[{"type":"field","inboundTag":["qa-in"],"ip":[target+("/32" if probe.endswith("4") else "/128")],"port":"39883","network":network,"outboundTag":"receipt-only"}]}}


def rotate_reality_key(server, fixture):
    """Change server key only; return a matching positive-control URI."""
    private, public = keypair()
    parts = urlsplit(fixture.strip())
    query = parse_qsl(parts.query, strict_parsing=True)
    assert sum(k=="pbk" for k,v in query)==1
    new = url64(public)
    assert all(v!=new for k,v in query if k=="pbk")
    server["inbounds"][0]["streamSettings"]["realitySettings"]["privateKey"]=url64(private)
    return urlunsplit(parts._replace(query=urlencode([(k,new if k=="pbk" else v) for k,v in query])))


def socks_udp_probe(target, challenge):
    """Local SOCKS5 UDP associate; fixed synthetic target only."""
    def exact(sock,n):
        result=b""
        while len(result)<n:
            part=sock.recv(n-len(result))
            if not part:raise OSError("closed")
            result+=part
        return result
    def address(sock,atyp):
        if atyp==1:return socket.inet_ntop(socket.AF_INET,exact(sock,4))
        if atyp==4:return socket.inet_ntop(socket.AF_INET6,exact(sock,16))
        raise ValueError("unexpected SOCKS address")
    try:
        with socket.create_connection((HOST,39879),timeout=7) as control:
            control.sendall(b"\x05\x01\x00")
            assert exact(control,2)==b"\x05\x00"
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as datagram:
                datagram.bind((HOST,0));datagram.settimeout(7)
                control.sendall(b"\x05\x03\x00\x01"+socket.inet_aton(HOST)+datagram.getsockname()[1].to_bytes(2,"big"))
                header=exact(control,4)
                assert header[:3]==b"\x05\x00\x00"
                host=address(control,header[3]);port=int.from_bytes(exact(control,2),"big")
                assert host in (HOST,"0.0.0.0") and port>0
                ip=ipaddress.ip_address(target)
                packet=b"\x00\x00\x00"+bytes([1 if ip.version==4 else 4])+ip.packed+(39883).to_bytes(2,"big")
                datagram.sendto(packet+("APL_UDP:"+challenge).encode(),(HOST,port))
                response,src=datagram.recvfrom(512)
                assert src==(HOST,port) and response[:3]==b"\x00\x00\x00"
                size={1:4,4:16}.get(response[3])
                return size is not None and response[4+size+2:]==("APL_RECEIPT:"+challenge).encode()
    except (OSError,TimeoutError):return False

def run(root, peer, command, preflight_only=False):
    assert root.is_dir() and root.stat().st_mode & 0o077 == 0
    nonce=secrets.token_hex(20)
    item=None
    if command:
        item=json.loads(command.read_text())
        validate_command(item)
        assert item["action"]=="run" and item["reference"]["kind"]=="vlessReality" and (item.get("scope")=="vlessDatagrams" or (item.get("scope") is None and item["probe"]=="tcp4")) and item["mode"] in ("positive","wrong-key")
        nonce=item["nonce"]
    work=root/("witness-"+str(uuid.uuid4()))
    work.mkdir(mode=0o700)
    pre=secrets.token_hex(20)
    seen=[];counts=[0,0,0];lock=threading.Lock();stop=threading.Event()
    negative=item is not None and item["mode"]=="wrong-key"
    probe=item["probe"] if item else "tcp4"
    target=TARGET if probe.endswith("4") else "2001:db8:77::77"
    udp=probe.startswith("udp")
    server=config(root,probe)
    original=(root/"fixture.txt").read_text()
    control=rotate_reality_key(server, original) if negative else original
    conf=work/"server.json";conf.write_text(json.dumps(server))
    cert,key=work/"tls.crt",work/"tls.key"
    subprocess.run(["openssl","req","-x509","-newkey","rsa:2048","-nodes","-keyout",str(key),"-out",str(cert),"-days","1","-subj","/CN=example.com"],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version=ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(cert,key)
    ctx.set_alpn_protocols(["h2","http/1.1"])
    class Witness(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in ("/"+nonce,"/"+pre):self.send_error(404);return
            body=("APL_RECEIPT:"+self.path[1:]).encode()
            self.send_response(200);self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body)
            with lock:seen.append(self.path[1:])
        def log_message(self,*_):pass
    class UDPWitness(socketserver.BaseRequestHandler):
        def handle(self):
            raw,sock=self.request
            if raw not in (("APL_UDP:"+nonce).encode(),("APL_UDP:"+pre).encode()):return
            challenge=raw[8:].decode("ascii")
            sock.sendto(("APL_RECEIPT:"+challenge).encode(),self.client_address)
            with lock:seen.append(challenge)
    class Server(socketserver.ThreadingTCPServer):
        daemon_threads=True
        allow_reuse_address=True
    class Relay(socketserver.BaseRequestHandler):
        def handle(self):
            self.request.settimeout(5)
            try:
                with socket.create_connection((HOST,PORT),timeout=3) as upstream:
                    until=time.monotonic()+18
                    while not stop.is_set() and time.monotonic()<until:
                        ready,_,_=select.select([self.request,upstream],[],[],.2)
                        for src in ready:
                            data=src.recv(65536)
                            if not data:return
                            with lock:counts[1 if src is self.request else 2]+=len(data)
                            (upstream if src is self.request else self.request).sendall(data)
            except OSError:return
    class LANServer(Server):
        def verify_request(self,request,address):
            if ipaddress.ip_address(address[0]) not in ipaddress.ip_network("192.168.1.0/24"):return False
            with lock:
                if counts[0]>=8:return False
                counts[0]+=1
            return not stop.is_set()
    class Decoy(socketserver.BaseRequestHandler):
        def handle(self):
            self.request.settimeout(3)
            try:
                with ctx.wrap_socket(self.request,server_side=True) as s:
                    if s.selected_alpn_protocol()!="h2" and s.recv(4096).startswith(b"GET "):
                        s.sendall(b"HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nOK")
            except OSError:pass
    servers=[];process=None
    try:
        for s in ((socketserver.ThreadingUDPServer((HOST,39883),UDPWitness) if udp else http.server.ThreadingHTTPServer((HOST,39883),Witness)),LANServer((LAN,PORT),Relay),Server((HOST,39884),Decoy)):
            threading.Thread(target=s.serve_forever,daemon=True).start();servers.append(s)
        log=work/"server.log"
        with log.open("w") as out:process=subprocess.Popen([str(peer),"server",str(conf),str(PORT)],stdout=out,stderr=subprocess.STDOUT)
        wait_for(process,log,"PEER_QA_READY_server")
        def local_probe(label,uri,challenge,success):
            client=work/(label+".uri");client.write_text(uri)
            clog=work/(label+".log")
            with clog.open("w") as out:p=subprocess.Popen([str(peer),"client",str(client),"39879"],stdout=out,stderr=subprocess.STDOUT,env=dict(os.environ,APL_PHYSICAL_PEER_DATAGRAMS="1" if udp else "0"))
            try:
                wait_for(p,clog,"PEER_QA_READY_client")
                if udp:
                    matched=socks_udp_probe(target,challenge)
                else:
                    authority=target if probe.endswith("4") else "["+target+"]"
                    got=subprocess.run(["curl","--disable","--noproxy","","--silent","--max-time","7","--socks5-hostname",HOST+":39879","http://"+authority+":39883/"+challenge],capture_output=True,env={k:v for k,v in os.environ.items() if "proxy" not in k.lower()})
                    matched=got.returncode==0 and got.stdout==("APL_RECEIPT:"+challenge).encode()
                assert matched==success,"local witness preflight mismatch"
            finally:
                Path(str(client)+".stop").touch();p.wait(timeout=7)
            assert p.returncode==0
        local_probe("positive-control",control,pre,True)
        if negative:
            local_probe("wrong-key-control",original,nonce,False)
        with lock:
            assert seen==[pre]
            baseline=counts.copy()
        print("NATIVELAB_VLESS_PEER_READY",flush=True)
        if not item or preflight_only:return 0
        deadline=time.monotonic()+48
        while time.monotonic()<deadline and not (root/("stop-"+item["requestID"])).exists():time.sleep(.1)
        with lock:
            result={"schema":1,"probe":probe,"mode":item["mode"],"localPositiveControl":True,"localNegativeControl":negative,"requestID":item["requestID"],"challengeSHA256":hashlib.sha256(nonce.encode()).hexdigest(),"witnessCount":seen.count(nonce),"relayAccepted":counts[0]-baseline[0],"ingressBytes":counts[1]-baseline[1],"egressBytes":counts[2]-baseline[2],"responseSHA256":hashlib.sha256(("APL_RECEIPT:"+nonce).encode()).hexdigest() if seen.count(nonce)==1 else None,"release_authorized":False}
        (work/"peer-observation.json").write_text(json.dumps(result,sort_keys=True)+"\n")
        print("NATIVELAB_VLESS_PEER_OBSERVATION",json.dumps(result),flush=True)
        return 0 if result["witnessCount"]==(0 if negative else 1) and result["relayAccepted"]>0 and result["ingressBytes"]>0 and result["egressBytes"]>0 else 2
    finally:
        stop.set()
        for s in servers:s.shutdown();s.server_close()
        if process:
            Path(str(conf)+".stop").touch()
            process.wait(timeout=7)
            assert process.returncode==0,"peer shutdown failed"


if __name__=="__main__":
    os.umask(0o077)
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("root",type=Path);p.add_argument("peer",type=Path);p.add_argument("--command",type=Path)
    p.add_argument("--preflight-only",action="store_true")
    a=p.parse_args()
    raise SystemExit(run(a.root,a.peer,a.command,a.preflight_only))
