#!/usr/bin/env python3
"""Finite private-LAN witness, one synthetic VLESS target and transport only."""
import argparse, hashlib, http.server, ipaddress, json, os
from pathlib import Path
import secrets, select, socket, socketserver, ssl, subprocess
import threading, time, uuid
from native_runtime_qa_receipt import validate_command, post_loss_nonce
from run_xray_vless_peer_qa import wait_for
from unified_synthetic_fixture import keypair, url64
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

LAN, HOST, TARGET, PORT = "192.168.1.80", "127.0.0.1", "198.51.100.77", 39882


class TLSFirstRecordMeter:
    """Observe only TLS record header/length, never any client payload or SNI."""
    def __init__(self):
        self._prefix = bytearray()
        self.client_bytes = 0

    def feed(self, chunk):
        if len(self._prefix) < 5:
            self._prefix.extend(chunk[:5 - len(self._prefix)])
        self.client_bytes += len(chunk)

    def summary(self):
        result = {"clientBytes": self.client_bytes, "tlsHeader": "incomplete"}
        if len(self._prefix) < 5:
            return result
        prefix = self._prefix
        length = int.from_bytes(prefix[3:5], "big")
        if prefix[0] != 22 or prefix[1] != 3 or prefix[2] not in (1, 2, 3, 4) or not (1 <= length <= 18432):
            result["tlsHeader"] = "notHandshakeRecord"
            return result
        result["tlsHeader"] = "handshakeRecordHeader"
        result["expectedFirstRecordBytes"] = length + 5
        result["firstRecordComplete"] = self.client_bytes >= length + 5
        return result


def dns_wire_query(challenge):
    import re
    assert re.fullmatch("[0-9a-f]{40}",challenge)
    return bytes.fromhex("a11701000001000000000000")+b"".join(bytes([len(label)])+label for label in (challenge.encode(),b"apl",b"invalid"))+bytes.fromhex("0000010001")


def dns_wire_response(challenge):
    return bytes.fromhex("a11781800001000100000000")+dns_wire_query(challenge)[12:]+bytes.fromhex("c00c00010001000000000004c0000235")


def config(root, probe="tcp4"):
    assert probe in ("tcp4","tcp6","udp4","udp6","dnsWire4")
    target=TARGET if probe.endswith("4") else "2001:db8:77::77"
    network="udp" if probe=="dnsWire4" else probe[:3]
    target_port="53" if probe=="dnsWire4" else "39883"
    # Use only the ephemeral keys from the private fixture, not arbitrary routing.
    i=json.loads((root/"peer.json").read_text())["inbounds"][0]
    uid=i["settings"]["clients"][0]["id"]
    reality=i["streamSettings"]["realitySettings"]
    key,sid=reality["privateKey"],reality["shortIds"][0]
    assert str(uuid.UUID(uid))==uid
    import base64,re
    assert re.fullmatch(r"[A-Za-z0-9_-]{43}",key) and len(base64.urlsafe_b64decode(key+"="))==32
    assert re.fullmatch(r"[a-f0-9]{16}",sid)
    return {"log":{"loglevel":"none"},"inbounds":[{"tag":"qa-in","listen":HOST,"port":PORT,"protocol":"vless","settings":{"clients":[{"id":uid}],"decryption":"none"},"streamSettings":{"network":"raw","security":"reality","realitySettings":{"target":HOST+":39884","serverNames":["example.com"],"privateKey":key,"shortIds":[sid]}}}],"outbounds":[{"tag":"deny","protocol":"blackhole"},{"tag":"receipt-only","protocol":"freedom","settings":{"redirect":HOST+":39883","finalRules":[{"action":"allow","network":network,"port":"39883","ip":[HOST+"/32"]},{"action":"block"}]}}],"routing":{"domainStrategy":"AsIs","rules":[{"type":"field","inboundTag":["qa-in"],"ip":[target+("/32" if probe.endswith("4") else "/128")],"port":target_port,"network":network,"outboundTag":"receipt-only"}]}}


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


def socks_udp_probe(target, challenge, dns=False):
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
                packet=b"\x00\x00\x00"+bytes([1 if ip.version==4 else 4])+ip.packed+(53 if dns else 39883).to_bytes(2,"big")
                datagram.sendto(packet+(dns_wire_query(challenge) if dns else ("APL_UDP:"+challenge).encode()),(HOST,port))
                response,src=datagram.recvfrom(512)
                assert src==(HOST,port) and response[:3]==b"\x00\x00\x00"
                size={1:4,4:16}.get(response[3])
                return size is not None and response[4+size+2:]==(dns_wire_response(challenge) if dns else ("APL_RECEIPT:"+challenge).encode())
    except (OSError,TimeoutError):return False

def run(root, peer, command, preflight_only=False):
    assert root.is_dir() and root.stat().st_mode & 0o077 == 0
    nonce=secrets.token_hex(20)
    item=None
    if command:
        item=json.loads(command.read_text())
        validate_command(item)
        assert item["action"]=="run" and item["reference"]["kind"]=="vlessReality" and (item.get("scope") in ("vlessDatagrams","vlessDNSWire","vlessGuardedLoss") or (item.get("scope") is None and item["probe"]=="tcp4")) and item["mode"] in ("positive","wrong-key","peer-loss")
        nonce=item["nonce"]
    work=root/("witness-"+str(uuid.uuid4()))
    work.mkdir(mode=0o700)
    pre=secrets.token_hex(20)
    seen=[];counts=[0,0,0];first_records=[];lock=threading.Lock();stop=threading.Event()
    negative=item is not None and item["mode"]=="wrong-key"
    loss=item is not None and item["mode"]=="peer-loss"
    second=post_loss_nonce(item) if loss else None
    cut=threading.Event()
    loss_times={}
    active=set()
    def cut_relay():
        with lock:
            cut.set()
            loss_times["cutAt"]=time.time()
            sockets=list(active)
        for sock in sockets:
            try:sock.shutdown(socket.SHUT_RDWR)
            except OSError:pass
        print("NATIVELAB_VLESS_RELAY_CUT",flush=True)
    probe=item["probe"] if item else "tcp4"
    target=TARGET if probe.endswith("4") else "2001:db8:77::77"
    dns=probe=="dnsWire4"
    udp=probe.startswith("udp") or dns
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
            if dns:
                challenge=next((n for n in (nonce,pre) if raw==dns_wire_query(n)),None)
                if challenge is None:return
                sock.sendto(dns_wire_response(challenge),self.client_address)
                with lock:seen.append(challenge)
                return
            if loss and raw==("APL_UDP:"+second).encode():
                with lock:seen.append(second)
                return
            if raw not in (("APL_UDP:"+nonce).encode(),("APL_UDP:"+pre).encode()):return
            challenge=raw[8:].decode("ascii")
            sock.sendto(("APL_RECEIPT:"+challenge).encode(),self.client_address)
            with lock:
                seen.append(challenge)
                if loss and challenge==nonce and "firstAt" not in loss_times:
                    loss_times["firstAt"]=time.time()
                    timer=threading.Timer(.5,cut_relay)
                    timer.daemon=True
                    timer.start()
    class Server(socketserver.ThreadingTCPServer):
        daemon_threads=True
        allow_reuse_address=True
    class Relay(socketserver.BaseRequestHandler):
        def handle(self):
            meter = TLSFirstRecordMeter()
            with lock:
                first_records.append(meter)
            self.request.settimeout(5)
            try:
                with socket.create_connection((HOST,PORT),timeout=3) as upstream:
                    with lock:
                        if cut.is_set():return
                        active.update((self.request,upstream))
                    until=time.monotonic()+18
                    while not stop.is_set() and not cut.is_set() and time.monotonic()<until:
                        ready,_,_=select.select([self.request,upstream],[],[],.2)
                        for src in ready:
                            data=src.recv(65536)
                            if not data:return
                            with lock:
                                counts[1 if src is self.request else 2]+=len(data)
                                if src is self.request:meter.feed(data)
                            (upstream if src is self.request else self.request).sendall(data)
            except OSError:return
            finally:
                with lock:
                    active.discard(self.request)
                    if "upstream" in locals():active.discard(upstream)
    class LANServer(Server):
        def verify_request(self,request,address):
            if ipaddress.ip_address(address[0]) not in ipaddress.ip_network("192.168.1.0/24"):return False
            with lock:
                if cut.is_set():
                    loss_times["postCutAttempts"]=loss_times.get("postCutAttempts",0)+1
                    return False
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
                    matched=socks_udp_probe(target,challenge,dns)
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
            # Assert the local positive control actually carried a complete TLS
            # record. Otherwise physical "no ClientHello" conclusions are unsound.
            assert any(
                m.summary().get("tlsHeader") == "handshakeRecordHeader" and
                m.summary().get("firstRecordComplete")
                for m in first_records
            ), "local positive-control TLS record not observed"
            baseline=counts.copy()
            first_record_baseline=len(first_records)
        print("NATIVELAB_VLESS_PEER_READY",flush=True)
        if not item or preflight_only:return 0
        deadline=time.monotonic()+48
        while time.monotonic()<deadline and not (root/("stop-"+item["requestID"])).exists():time.sleep(.1)
        with lock:
            result={"schema":1,"probe":probe,"mode":item["mode"],"localPositiveControl":True,"localNegativeControl":negative,"requestID":item["requestID"],"challengeSHA256":hashlib.sha256(nonce.encode()).hexdigest(),"witnessCount":seen.count(nonce),"relayAccepted":counts[0]-baseline[0],"ingressBytes":counts[1]-baseline[1],"egressBytes":counts[2]-baseline[2],"firstTLSRecords":[meter.summary() for meter in first_records[first_record_baseline:first_record_baseline+8]],"responseSHA256":hashlib.sha256(dns_wire_response(nonce) if dns else ("APL_RECEIPT:"+nonce).encode()).hexdigest() if seen.count(nonce)==1 else None,"release_authorized":False}
            if loss:
                result.update(loss=dict(loss_times,secondChallengeSHA256=hashlib.sha256(second.encode()).hexdigest(),secondWitnessCount=seen.count(second),relayCut=cut.is_set(),activeAfterCut=len(active)))
        (work/"peer-observation.json").write_text(json.dumps(result,sort_keys=True)+"\n")
        print("NATIVELAB_VLESS_PEER_OBSERVATION",json.dumps(result),flush=True)
        if loss and not (cut.is_set() and 0<=loss_times.get("cutAt",0)-loss_times.get("firstAt",0)<=1.5 and seen.count(second)==0 and not active):
            return 2
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
