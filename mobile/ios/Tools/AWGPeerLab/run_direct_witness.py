"""Supervised, finite native QA witness; independent exact-device peer."""
import base64,configparser,hashlib,json,os,secrets,subprocess,sys,time
from pathlib import Path
from contextlib import contextmanager
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from native_runtime_qa_receipt import validate_command
from adapt_unified_awg_peer_receipt import parse_terminal
from unified_synthetic_fixture import keypair
KINDS=("tcp4","tcp6","udp4","udp6")
@contextmanager
def server(binary,folder,cfg):
    folder.mkdir(mode=0o700)
    path=folder/"server.json";path.write_text(json.dumps(cfg))
    log=folder/"server.log"
    with log.open("w") as f:
        p=subprocess.Popen([str(binary),"server",str(path)],stdout=f,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+15
            while "AWG_PEER_READY" not in log.read_text():
                assert p.poll() is None and time.monotonic()<deadline
                time.sleep(.1)
            yield
        finally:
            Path(str(path)+".stop").touch()
            try:p.wait(timeout=12)
            except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=5)
            path.unlink(missing_ok=True)
            assert p.returncode==0
def run(root,case):
    binary=root/"direct-reference/awg-reference"
    assert hashlib.sha256(binary.read_bytes()).hexdigest()==(binary.parent/"SHA256SUMS").read_text().split()[0]
    folder=root/case;item=json.loads((folder/"apl-native-runtime-qa-command.json").read_text());validate_command(item)
    assert item["action"]=="run" and item["reference"]==json.loads((root/"fixture-ref.json").read_text())["reference"]
    assert item["reference"]["kind"]=="amneziaWG1" and item["owner"]==(root/"owner").read_text().strip()
    cfg=json.loads((root/"peer.json").read_text());assert cfg["ClientIP"]=="192.168.1.90"
    f=configparser.ConfigParser();f.read(root/"fixture.txt")
    key=lambda section,name:base64.b64decode(f[section][name],validate=True).hex()
    orig=dict(Private=key("Interface","PrivateKey"),Peer=key("Peer","PublicKey"),PSK=key("Peer","PresharedKey"),ClientIP="192.168.1.80")
    assert cfg["PSK"]==orig["PSK"]
    matching=dict(orig);mode=item["mode"]
    if mode=="wrong-key":
        priv,pub=keypair();cfg["Private"]=priv.hex();matching["Peer"]=pub.hex()
        assert matching["Peer"]!=orig["Peer"]
    if mode=="wrong-psk":
        cfg["PSK"]=secrets.token_hex(32);matching["PSK"]=cfg["PSK"]
        assert matching["PSK"]!=orig["PSK"]
    def control(keys,positive,name):
        nonce=secrets.token_hex(24);d=folder/name
        with server(binary,d,dict(cfg,ClientIP="192.168.1.80",Nonce=nonce)):
            path=d/"client.json";path.write_text(json.dumps(dict(keys,Nonce=nonce)))
            try:
                result=subprocess.run([str(binary),"positive" if positive else "negative",str(path)],capture_output=True,timeout=25)
                assert result.returncode==0
            finally:path.unlink(missing_ok=True)
        counts=parse_terminal((d/"server.log").read_text(),0)
        assert counts[:4]==((1,1,1,1) if positive else (0,0,0,0)) and counts[5]>0 and (not positive or counts[4]>0)
    control(matching,True,"local-positive")
    if mode!="positive":control(orig,False,"local-negative")
    print("AWG_LOCAL_CONTROLS_PASS",mode,flush=True)
    d=folder/"physical";nonce=item["nonce"]
    with server(binary,d,dict(cfg,Nonce=nonce)):
        print("AWG_PHYSICAL_READY",item["requestID"],flush=True)
        deadline=time.monotonic()+100
        while time.monotonic()<deadline and not (folder/"stop").exists():time.sleep(.1)
    counts=parse_terminal((d/"server.log").read_text(),0)
    expected=tuple(int(mode=="positive" and k==item["probe"]) for k in KINDS)
    observation=dict(requestID=item["requestID"],mode=mode,probe=item["probe"],challengeSHA256=hashlib.sha256(nonce.encode()).hexdigest(),witnessCounts=dict(zip(KINDS,counts[:4])),sent=counts[4],received=counts[5],rejected=counts[6],responseSHA256=hashlib.sha256(("APL:"+nonce).encode()).hexdigest() if mode=="positive" and counts[:4]==expected else None,localPositiveControl=True,localNegativeControl=mode!="positive")
    (folder/"peer-observation.json").write_text(json.dumps(observation)+"\n")
    print(json.dumps(observation),flush=True)
    assert counts[:4]==expected and counts[5]>0 and (mode!="positive" or counts[4]>0) and (mode!="wrong-key" or counts[4]==0)
if __name__=="__main__":
    os.umask(0o077);run(Path(sys.argv[1]),sys.argv[2])
