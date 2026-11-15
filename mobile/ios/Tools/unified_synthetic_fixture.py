#!/usr/bin/env python3
"""Generate private, one-run synthetic input only. No listeners or device calls."""
import argparse,base64,hashlib,json,os,pathlib,secrets,subprocess,uuid

CANDIDATE='f4e606ba72747421c4487bbe5007d6fd8719583fd66136d9f6f1ce3bf65f7c4e'
CONTAINING_CANDIDATE='5f62a044d12ca4473d93fb38f5e27ea91c7e49d12720168b2ce6be37f9190dc4'
CANDIDATES=(CANDIDATE,CONTAINING_CANDIDATE)
CASES={'wireGuard':('tcp4','tcp6','udp4','udp6'),'amneziaWG1':('tcp4','tcp6','udp4','udp6'),'vlessReality':('tcp4',)}
MODES={'wireGuard':('positive','wrong-key'),'amneziaWG1':('positive','wrong-key','wrong-psk'),'vlessReality':('positive','wrong-key')}

def uid():return str(uuid.uuid4()).upper()
def b64(x):return base64.b64encode(x).decode()
def url64(x):return base64.urlsafe_b64encode(x).decode().rstrip('=')
def digest(x):return hashlib.sha256(x).hexdigest()
def json_digest(x):return digest(json.dumps(x,sort_keys=True,separators=(",",":")).encode())
def keypair():
    p=subprocess.check_output(['openssl','genpkey','-algorithm','X25519','-outform','DER'],timeout=5)
    q=subprocess.check_output(['openssl','pkey','-inform','DER','-pubout','-outform','DER'],input=p,timeout=5)
    if len(p)!=48 or not p.startswith(bytes.fromhex('302e020100300506032b656e04220420')) or len(q)!=44 or not q.startswith(bytes.fromhex('302a300506032b656e032100')):raise ValueError('unexpected key encoding')
    return p[-32:],q[-32:]

def generate(kind,probe,mode,local,candidate=CONTAINING_CANDIDATE):
    if candidate not in CANDIDATES:raise ValueError('unknown compile candidate')
    if kind not in CASES or probe not in CASES[kind] or mode not in MODES[kind]:raise ValueError('unsupported fixture case')
    if kind=='amneziaWG1':
        if type(local)!=int or local>>8!=0xc0a801 or not 1<=local&255<=254 or local&255==80:raise ValueError('explicit non-peer QA LAN client required')
    elif local is not None:raise ValueError('unexpected client address')
    from ipaddress import IPv4Address
    cp,cu=keypair();sp,su=keypair();_,wrong=keypair();psk=secrets.token_bytes(32)
    w=wrong if mode=='wrong-key' else su
    nonce=secrets.token_hex(24 if kind=='amneziaWG1' else 20)
    if kind=='wireGuard':
        fixture=(' [Interface]\nPrivateKey = '+b64(cp)+'\nAddress = 10.77.0.2/32, 2001:db8:77::2/128\n[Peer]\nPublicKey = '+b64(w)+'\nPresharedKey = '+b64(psk)+'\nEndpoint = 192.168.1.80:39881\nAllowedIPs = 198.51.100.77/32, 2001:db8:77::77/128\n').lstrip().encode()
        server={'private':sp.hex(),'peer':cu.hex(),'psk':psk.hex(),'dual':True,'nonce':nonce}
    elif kind=='amneziaWG1':
        fixture=cp+w+(secrets.token_bytes(32) if mode=='wrong-psk' else psk)
        server={'Private':sp.hex(),'Peer':cu.hex(),'PSK':psk.hex(),'Nonce':nonce,'ClientIP':str(IPv4Address(local))}
    else:
        user=uid().lower();sid=secrets.token_hex(8)
        fixture=f'vless://{user}@192.168.1.80:39882?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk={url64(w)}&sid={sid}'.encode()
        server={'log':{'loglevel':'none'},'inbounds':[{'tag':'qa-in','listen':'127.0.0.1','port':39882,'protocol':'vless','settings':{'clients':[{'id':user}],'decryption':'none'},'streamSettings':{'network':'raw','security':'reality','realitySettings':{'target':'127.0.0.1:39884','serverNames':['example.com'],'privateKey':url64(sp),'shortIds':[sid]}}}],'outbounds':[{'tag':'deny','protocol':'blackhole'},{'tag':'receipt-only','protocol':'freedom','settings':{'redirect':'127.0.0.1:39883','finalRules':[{'action':'allow','network':'tcp','port':'39883','ip':['127.0.0.1/32']},{'action':'block'}]}}],'routing':{'domainStrategy':'AsIs','rules':[{'type':'field','inboundTag':['qa-in'],'ip':['198.51.100.77/32'],'port':'39883','network':'tcp','outboundTag':'receipt-only'}]}}
    run=uid();owner=uid();identity={'epoch':uid(),'generation':1,'provider':'standalone-awg' if kind=='amneziaWG1' else 'rust-xray'}
    public={'schema':1,'runID':run,'owner':owner,'identity':identity,'kind':kind,'probe':probe,'mode':mode,'candidateManifestSHA256':candidate,'challengeSHA256':digest(nonce.encode()),'fixtureSHA256':digest(fixture),'peerInputSHA256':json_digest(server),'runtime_authorized':False}
    private={'runID':run,'owner':owner,'identity':identity,'kind':kind,'probe':probe,'mode':mode,'nonce':nonce,'fixture':b64(fixture),'localIPv4':local}
    return public,private,server

def witness_input(public,private):
    return {**{k:public[k] for k in ('runID','candidateManifestSHA256','peerInputSHA256','challengeSHA256','kind','probe','mode')},'nonce':private['nonce']}

def write(root,kind,probe,mode,local,candidate=CONTAINING_CANDIDATE):
    public,private,server=generate(kind,probe,mode,local,candidate)
    root.mkdir(mode=0o700)
    for name,data in [('manifest.json',public),('host-input.json',private),('peer-input.json',server),('witness-input.json',witness_input(public,private))]:
        fd=os.open(root/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'w') as f:json.dump(data,f,sort_keys=True,indent=2);f.write('\n')
    return public

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=pathlib.Path);p.add_argument('kind',choices=CASES);p.add_argument('probe');p.add_argument('mode');p.add_argument('--local-ipv4',type=int);a=p.parse_args()
    m=write(a.output,a.kind,a.probe,a.mode,a.local_ipv4);print('PRIVATE_FIXTURE_CREATED',m['runID'],m['kind'],m['probe'],m['mode'])
