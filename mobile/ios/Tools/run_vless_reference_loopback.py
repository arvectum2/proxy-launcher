#!/usr/bin/env python3
"""Pinned local Xray reference processes and a fixed localhost witness only."""
import base64,contextlib,hashlib,http.server,json,os,pathlib,select,socket,socketserver,ssl,subprocess,sys,tempfile,threading,time
from unified_synthetic_fixture import generate,digest
from run_xray_vless_peer_qa import wait_for
HOST='127.0.0.1'

@contextlib.contextmanager
def process(binary,role,path,port):
    log=path.with_suffix('.log')
    with log.open('w') as f:
        p=subprocess.Popen([str(binary),role,str(path),str(port)],stdout=f,stderr=subprocess.STDOUT)
        try:
            wait_for(p,log,'PEER_QA_READY_'+role,8);yield
        finally:
            pathlib.Path(str(path)+'.stop').touch()
            try:p.wait(timeout=7)
            except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=5)
            if p.returncode or log.read_text().splitlines().count('PEER_QA_STOPPED_'+role)!=1:raise RuntimeError('reference process drain unconfirmed')

@contextlib.contextmanager
def serve(server):
    t=threading.Thread(target=server.serve_forever);t.start()
    try:yield
    finally:server.shutdown();server.server_close();t.join(5)

def case(binary,root,mode):
    m,private,peer=generate('vlessReality','tcp4',mode,None)
    nonce=private['nonce'];body=('APL_RECEIPT:'+nonce).encode();counts=[0,0];seen=[];lock=threading.Lock()
    class Witness(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path!='/'+nonce:self.send_error(404);return
            self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body);self.wfile.flush()
            with lock:seen.append(digest(body))
        def log_message(self,*args):pass
    class Relay(socketserver.BaseRequestHandler):
        def handle(self):
            self.request.settimeout(3)
            try:
                with socket.create_connection((HOST,39880),timeout=2) as upstream:
                    upstream.settimeout(3);end=time.monotonic()+12
                    while time.monotonic()<end:
                        ready,_,_=select.select([self.request,upstream],[],[],.2)
                        for src in ready:
                            data=src.recv(16384)
                            if not data:return
                            idx=0 if src is self.request else 1
                            (upstream if idx==0 else self.request).sendall(data)
                            with lock:
                                counts[idx]+=len(data)
                                if counts[idx]>1048576:return
            except OSError:return
    class LocalServer(socketserver.ThreadingTCPServer):
        allow_reuse_address=True;daemon_threads=False
        def verify_request(self,request,address):return address[0]==HOST
    class LocalWitness(http.server.ThreadingHTTPServer):
        daemon_threads=False
    peer['inbounds'][0]['port']=39880
    server=root/'server.json';server.write_text(json.dumps(peer));client=root/'client.uri';uri=base64.b64decode(private['fixture']).decode();assert uri.count('@192.168.1.80:39882')==1;client.write_text(uri.replace('@192.168.1.80:39882','@127.0.0.1:39882'))
    cert=root/'tls.crt';key=root/'tls.key';subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=example.com'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.minimum_version=ssl.TLSVersion.TLSv1_3;ctx.load_cert_chain(cert,key);ctx.set_alpn_protocols(['h2','http/1.1'])
    class Decoy(socketserver.BaseRequestHandler):
        def handle(self):
            self.request.settimeout(3)
            try:
                with ctx.wrap_socket(self.request,server_side=True) as s:
                    if s.selected_alpn_protocol()!='h2' and s.recv(4096).startswith(b'GET '):s.sendall(b'HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nOK')
            except OSError:pass
    with serve(LocalServer((HOST,39884),Decoy)):
        check=ssl.create_default_context();check.check_hostname=False;check.verify_mode=ssl.CERT_NONE;check.minimum_version=ssl.TLSVersion.TLSv1_3;check.set_alpn_protocols(['http/1.1'])
        with socket.create_connection((HOST,39884),timeout=2) as raw:
            with check.wrap_socket(raw,server_hostname='example.com') as s:
                s.sendall(b'GET / HTTP/1.0\r\nHost: example.com\r\n\r\n');assert s.recv(256).startswith(b'HTTP/')
        with serve(LocalWitness((HOST,39883),Witness)),process(binary,'server',server,39880),serve(LocalServer((HOST,39882),Relay)):
            with process(binary,'client',client,39879):
                r=subprocess.run(['curl','--disable','--noproxy','','--silent','--show-error','--max-time','7','--socks5-hostname',HOST+':39879','http://198.51.100.77:39883/'+nonce],capture_output=True,env={k:v for k,v in os.environ.items() if 'proxy' not in k.lower()},timeout=10)
                ok=r.returncode==0 and r.stdout==body
    if ok!=(mode=='positive') or seen!=([digest(body)] if ok else []) or counts[0]==0 or (ok and counts[1]==0):raise RuntimeError(f'VLESS witness mismatch: mode={mode} curl={r.returncode} reply={ok} witness={len(seen)} ingress={counts[0]} egress={counts[1]}')
    return {'mode':mode,'witnessCount':len(seen),'ingressBytes':counts[0],'egressBytes':counts[1],'scope':'reference VLESS localhost only; changed fixed server listen port, not physical fixture','runtime_authorized':False}

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('usage: run_vless_reference_loopback.py VERIFIED_BINARY SHA256')
    binary=pathlib.Path(sys.argv[1]).resolve()
    if hashlib.sha256(binary.read_bytes()).hexdigest()!=sys.argv[2]:raise SystemExit('unreviewed binary')
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix='apl-vless-local-') as tmp:
        for mode in ('positive','wrong-key'):
            root=pathlib.Path(tmp)/mode;root.mkdir();print(json.dumps(case(binary,root,mode)),flush=True)
    print('VLESS_REFERENCE_LOOPBACK_ONLY_PASS')
