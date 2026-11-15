#!/usr/bin/env python3
"""Execute isolated reference peer processes on localhost only, not iOS QA."""
import argparse,hashlib,json,pathlib,secrets,subprocess,tempfile,time,os
from unified_synthetic_fixture import keypair
from adapt_unified_awg_peer_receipt import parse_terminal


def run(binary,root,mode):
    a,ap=keypair();b,bp=keypair();_,wrong=keypair();psk=secrets.token_hex(32);nonce=secrets.token_hex(24)
    common={'Nonce':nonce,'ClientIP':'127.0.0.1'}
    server=root/'server.json';client=root/'client.json';log=root/'peer.log'
    server.write_text(json.dumps(dict(common,Private=b.hex(),Peer=ap.hex(),PSK=psk)))
    client.write_text(json.dumps(dict(common,Private=a.hex(),Peer=(wrong if mode=='wrong-key' else bp).hex(),PSK=secrets.token_hex(32) if mode=='wrong-psk' else psk)))
    with log.open('w') as f:
        p=subprocess.Popen([str(binary),'server',str(server)],stdout=f,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+8
            while 'AWG_PEER_READY' not in log.read_text():
                if p.poll() is not None or time.monotonic()>=deadline:raise RuntimeError('loopback peer startup failed')
                time.sleep(.05)
            result=subprocess.run([str(binary),'positive' if mode=='positive' else 'negative',str(client)],capture_output=True,text=True,timeout=16)
            if result.returncode:raise RuntimeError('loopback client failed')
        finally:
            pathlib.Path(str(server)+'.stop').touch()
            try:p.wait(timeout=6)
            except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=5)
    counts=parse_terminal(log.read_text(),p.returncode)
    assert counts[:4]==((1,1,1,1) if mode=='positive' else (0,0,0,0)) and counts[5]>0 and (mode!='positive' or counts[4]>0)
    return {'mode':mode,'witnessCounts':list(counts[:4]),'sent':counts[4],'received':counts[5],'rejected':counts[6],'scope':'actual loopback reference engine only; not unified iOS runtime','runtime_authorized':False}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('binary',type=pathlib.Path);p.add_argument('sha256');args=p.parse_args();binary=args.binary.resolve()
    if hashlib.sha256(binary.read_bytes()).hexdigest()!=args.sha256:raise SystemExit('unreviewed loopback binary')
    os.umask(0o077);out=[]
    with tempfile.TemporaryDirectory(prefix='apl-awg-local-reference-') as t:
        for mode in ('positive','wrong-key','wrong-psk'):
            root=pathlib.Path(t)/mode;root.mkdir();out.append(run(binary,root,mode));print(json.dumps(out[-1]),flush=True)
    print('AWG_REFERENCE_LOOPBACK_ONLY_PASS',flush=True)
