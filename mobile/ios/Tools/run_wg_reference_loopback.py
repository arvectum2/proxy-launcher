#!/usr/bin/env python3
"""Two separate reference WireGuard processes, restricted localhost bind."""
import hashlib,json,os,pathlib,secrets,subprocess,sys,tempfile,time
from unified_synthetic_fixture import keypair
from adapt_unified_wg_peer_receipt import parse_terminal

def case(binary,root,mode):
    a,ap=keypair();b,bp=keypair();_,wrong=keypair();psk=secrets.token_hex(32);nonce=secrets.token_hex(20)
    common={'nonce':nonce,'dual':True};server=root/'server.json';client=root/'client.json';log=root/'server.log'
    server.write_text(json.dumps(dict(common,private=b.hex(),peer=ap.hex(),psk=psk)))
    client.write_text(json.dumps(dict(common,private=a.hex(),peer=(wrong if mode=='wrong-key' else bp).hex(),psk=psk)))
    with log.open('w') as f:
        p=subprocess.Popen([str(binary),'server',str(server),'39882'],stdout=f,stderr=subprocess.STDOUT)
        try:
            end=time.monotonic()+8
            while 'PEER_QA_READY_server' not in log.read_text():
                if p.poll() is not None or time.monotonic()>end:raise RuntimeError('server startup')
                time.sleep(.05)
            r=subprocess.run([str(binary),'positive' if mode=='positive' else 'negative',str(client),'39881'],capture_output=True,text=True,timeout=30)
            if r.returncode:raise RuntimeError('client failed: '+str(r.returncode)+' '+r.stdout)
        finally:
            pathlib.Path(str(server)+'.stop').touch()
            try:p.wait(timeout=10)
            except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=5)
    result=parse_terminal(log.read_text(),p.returncode)
    if result[:4]!=((1,1,1,1) if mode=='positive' else (0,0,0,0)) or result[5]==0 or (mode=='positive' and result[4]==0):raise RuntimeError('witness mismatch')
    return {'mode':mode,'witnessCounts':list(result[:4]),'sent':result[4],'received':result[5],'scope':'reference WG localhost only','runtime_authorized':False}

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('usage: run_wg_reference_loopback.py VERIFIED_BINARY SHA256')
    b=pathlib.Path(sys.argv[1]).resolve()
    if hashlib.sha256(b.read_bytes()).hexdigest()!=sys.argv[2]:raise SystemExit('unreviewed binary')
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix='apl-wg-local-') as tmp:
        for mode in ('positive','wrong-key'):
            root=pathlib.Path(tmp)/mode;root.mkdir();print(json.dumps(case(b,root,mode)),flush=True)
    print('WG_REFERENCE_LOOPBACK_ONLY_PASS')
