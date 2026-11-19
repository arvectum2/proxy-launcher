#!/usr/bin/env python3
"""Select product-only AWG C ABI and unchanged down-state support from pinned lab sources."""
import hashlib,json,sys
from pathlib import Path

ROOT=Path(__file__).resolve().parent
GO_PIN="2a318308d5bad67e1f00f8cd0027844537eea4b32ea33f574a56a9609811425a"
PRODUCT_EXPORTS={"aplAWGProductPrepare","aplAWGProductStart","aplAWGProductPush","aplAWGProductPull","aplAWGProductStop"}
ALLOWED_EXPORTS=PRODUCT_EXPORTS|{"CGoInvoke","CGoFree"}

def sha(data):return hashlib.sha256(data).hexdigest()

def require(ok,message):
    if not ok:raise ValueError(message)

def exact(path,want):
    data=path.read_bytes()
    require(sha(data)==want,"source mismatch: "+path.name)
    return data.decode()

def end_before(text,start,end):
    require(text.count(start)==text.count(end)==1,"ambiguous source boundary")
    a=text.index(start);b=text.index(end)
    require(a<b,"invalid source boundary")
    return text[a:b]

def prepare(receipt,dest,root=ROOT):
    import re
    raw=receipt.read_bytes();require(sha(raw)==GO_PIN,"Go receipt mismatch")
    m=json.loads(raw);require(m["product_awg_bridge"] is True and m["release_authorized"] is False,"wrong receipt")
    require({p.name for p in dest.glob("*.go")}=={"main.go"},"unexpected upstream bridge files")
    require(sha((dest/"main.go").read_bytes())==m["unified_bridge_sha256"]["main.go"],"Xray bridge mismatch")
    def lab(name):
        return exact(root/"AWGNativeLab"/name,m["original_bridge_sha256"][name])
    files={}
    for name,h in m["product_bridge_sha256"].items():
        require(Path(name).name==name and name in ("product_bind.go","product_bridge.go","product_tun.go"),"unexpected product source")
        files["awg_product_"+name]=exact(root/"AWGProductRuntime"/name,h)
    # Preserve the exact validation-only queue and endpoint operations.
    # No lab peer, listener, CLI or C entry point is copied.
    packet=lab("packet_bridge.go")
    queue=end_before(packet,"const bridgeMTU = 1280","type bridgePeer struct")
    ep=end_before(lab("main.go"),"type endpoint struct","type loop struct")
    scoped=end_before(lab("scoped_bind.go"),"type scopedEndpoint struct","type scopedBind struct")
    files["awg_product_support.go"]='package main\nimport ("encoding/binary";"github.com/amnezia-vpn/amneziawg-go/v3/tun";"net/netip";"os";"sync")\n'+queue+ep+scoped
    files["awg_product_validation.go"]=lab("product_config_validation.go")
    for name,text in files.items():
        with (dest/name).open("x") as f:f.write(text)
    exports={symbol for p in dest.glob("*.go") for symbol in re.findall(r"^//export (\w+)\s*$",p.read_text(),re.M)}
    require(exports==ALLOWED_EXPORTS,"unexpected bridge C export")
    return {p.name:sha(p.read_bytes()) for p in sorted(dest.glob("*.go"))}

if __name__=="__main__":
    print(json.dumps(prepare(Path(sys.argv[1]),Path(sys.argv[2])),sort_keys=True))
