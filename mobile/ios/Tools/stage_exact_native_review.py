#!/usr/bin/env python3
"""Private source review of the exercised isolated native lab, not release clearance."""
import hashlib,json,os,subprocess,sys,tarfile,tempfile,zipfile
from pathlib import Path,PurePosixPath
from audit_unified_go_notices import graph,UNIFIED
from stage_no_tproxy_source_review import verify_review
from stage_unified_source_review import sha,put,copy_verified
from verify_ios_native_exact_dns_receipt import EXACT_RECEIPT,EXACT_ARCHIVE

PINS={
 "base":("private-no-tproxy-source-review-20261115/manifest.json","52a291dce4a9c1efb0e9b3350c6832cd248f748baa8c7fa53e82cd27e1bc6c0e"),
 "rust":("tun2proxy-ios-native-exact-dns-20261115/manifest.json",EXACT_RECEIPT),
 "go":("product-unified-go-runtime-exact-peer-20261115/manifest.json","2a318308d5bad67e1f00f8cd0027844537eea4b32ea33f574a56a9609811425a"),
 "old_go":("product-unified-go-link-evidence-20261115/manifest.json",UNIFIED),
 "lab":("isolated-nativeqa-containing-20261116-2576a82d/manifest.json","9446d6781fa79c481d4f86a3c1bfb47364d3a6062af553cc1907e0273a609726")}
SOURCE="2576a82d9bb1ce17efbf58a74264f4aac08c7813"
SIGNED="6a6182626b749ec6948f577974b5701460355308e98a2bfa9d95ebaf507558ac"
ROOT=Path(__file__).resolve().parents[1]

def need(ok,message):
    if not ok:raise ValueError(message)

def digest(data):return hashlib.sha256(data).hexdigest()

def safe(name):
    p=PurePosixPath(name)
    need(bool(name) and not p.is_absolute() and ".." not in p.parts and str(p)==name and "\\" not in name,"unsafe path")
    return name

def checked(root,name,h):
    p=root/safe(name)
    need(p.is_file() and not p.is_symlink() and p.resolve().is_relative_to(root.resolve()) and sha(p)==h,"file mismatch: "+name)
    return p

def identity(row):
    m=row.get("Module",{});r=m.get("Replace",{})
    return tuple(x.get(k) for x in (m,r) for k in ("Path","Version","Sum","GoModSum"))

def compare_graphs(a,b):
    need(set(a)==set(b),"Go package set changed")
    need(all(identity(a[k])==identity(b[k]) for k in a),"Go module identity changed")
    return len(b)

def regularize_rust(source,expected,out):
    seen=set();members={}
    with tarfile.open(source,"r:gz") as t:
        for m in t:
            n=safe(m.name);need(n not in seen,"duplicate tar member");seen.add(n)
            if n==".dockerignore":
                need(m.issym() and m.linkname==".gitignore","unexpected dockerignore")
            else:
                need(m.isfile() and n in expected and 0<=m.size<=8*1024*1024,"unexpected tar member")
                data=t.extractfile(m).read();need(digest(data)==expected[n],"source member mismatch")
                members[n]=data
    need(seen==set(expected)|{".dockerignore"} and ".gitignore" in members,"incomplete Rust source")
    with zipfile.ZipFile(out,"x",compression=zipfile.ZIP_DEFLATED) as z:
        for n,data in sorted(members.items()):z.writestr(n,data)
        z.writestr(".dockerignore",members[".gitignore"])
    return len(members)

def stage(base,out):
    need(not out.exists() and not out.is_symlink(),"destination exists")
    os.umask(0o077);m={};folders={}
    for k,(name,h) in PINS.items():
        f=checked(base,name,h);m[k]=json.loads(f.read_text());folders[k]=f.parent
        need(m[k]["release_authorized"] is False,"unexpected release authorization")
    old=verify_review(folders["base"])
    for k in ("rust","go","old_go"):
        for n,h in m[k]["files"].items():checked(folders[k],n,h)
    lab=m["lab"]
    need(lab["source_commit"]==SOURCE and lab["isolated_nativeqa"] and lab["native_exact_dns"] and lab["product_awg_bridge"] and lab["product_runtime_review"],"lab scope mismatch")
    need(lab["rust_archive_sha256"]==m["rust"]["archive_sha256"]==EXACT_ARCHIVE and lab["go_archive_sha256"]==m["go"]["files"]["libAPLUnified.a"],"archive mapping mismatch")
    for n,h in lab["evidence"].items():checked(folders["lab"],n,h)
    for n,h in lab["bundle_files"].items():checked(folders["lab"]/"NativeLabHost.app",n,h)
    sign=checked(base,"isolated-nativeqa-signed-20261116-2576a82d/signed-manifest.json",SIGNED)
    sr=json.loads(sign.read_text())
    need(sr["source_commit"]==SOURCE and sr["unsigned_manifest_sha256"]==PINS["lab"][1] and sr["release_authorized"] is False,"signed provenance mismatch")
    for n,h in sr["signed_files"].items():checked(sign.parent/"NativeLabHost.app",n,h)
    for n in ("go.mod","go.sum"):need(m["go"]["files"][n]==m["old_go"]["files"][n],"Go lock changed")
    go_count=compare_graphs(graph(folders["old_go"]/"ios-deps.json"),graph(folders["go"]/"ios-deps.json"))
    for n in ("aarch64-apple-ios.tree","aarch64-apple-ios-sim.tree"):
        a=(folders["rust"]/n).read_text().splitlines();b=(folders["base"]/"rust"/n).read_text().splitlines()
        need(a[0].startswith("tun2proxy v0.8.3 ") and b[0].startswith("tun2proxy v0.8.3 ") and a[1:]==b[1:],"Rust graph changed")
    rs=json.loads((folders["rust"]/"exact-dns-source.json").read_text())
    need(rs["base_archive_sha256"]==old["rust_archive_sha256"] and rs["script_sha256"]==sha(ROOT/"Tools/prepare_native_exact_dns.py"),"Rust recipe drift")
    with tempfile.TemporaryDirectory(prefix=".apl-exact-review-",dir=out.parent) as temp:
        p=Path(temp)/"review";p.mkdir()
        for n,h in old["files"].items():
            if n.startswith(("xray/","awg/","mpl/","rust/notices/","rust/recipe/","sdk/")) or n in ("source/awg-b5928efb6ca19f0153958460c3d141f04abc5c2e.zip","source/libxray-5a0f7d8d1c28b34afb5727b04b26a10f6dbac7e3.zip"):
                copy_verified(folders["base"],n,h,p/n)
        for k in PINS:put(p/"evidence"/(k+".json"),(folders[k]/"manifest.json").read_bytes())
        put(p/"evidence/signed-manifest-digest.txt",(SIGNED+"\n").encode())
        for n in ("go.mod","go.sum","ios-deps.json"):
            copy_verified(folders["go"],n,m["go"]["files"][n],p/"go"/n)
        for name,h in m["go"]["unified_bridge_sha256"].items():
            safe(name)
            if name.removeprefix("awg_product_") in m["go"]["product_bridge_sha256"] and name.startswith("awg_product_"):
                data=(ROOT/"Tools/AWGProductRuntime"/name.removeprefix("awg_product_")).read_bytes()
            elif name.startswith("awg_"):
                data=(ROOT/"Tools/AWGNativeLab"/name.removeprefix("awg_")).read_bytes()
                if name=="awg_main.go":data=data.replace(b"func main() {",b"func awgSyntheticCLI() {",1)
            else:
                data=subprocess.check_output(["git","-C",str(base/"xray-source-20261115/libxray"),"show",m["go"]["xray_commit"]+":cgo_bridge/"+name],timeout=15)
            need(digest(data)==h,"Go bridge drift");put(p/"go/cgo_bridge"/name,data)
        for n in ("exact-dns-source.json","preparation.json","aarch64-apple-ios.tree","aarch64-apple-ios-sim.tree"):
            copy_verified(folders["rust"],n,m["rust"]["files"][n],p/"rust"/n)
        put(p/"rust/recipe/prepare_native_exact_dns.py",(ROOT/"Tools/prepare_native_exact_dns.py").read_bytes())
        count=regularize_rust(folders["rust"]/"source.tar.gz",rs["source_sha256"],p/"rust/exact-ios-source.zip")
        report={"schema":1,"release_authorized":False,"scope":"physically exercised isolated native candidate; historical SDK evidence only; not final product/legal clearance","source_commit":SOURCE,"unsigned_manifest_sha256":PINS["lab"][1],"signed_manifest_sha256":SIGNED,"go_archive_sha256":lab["go_archive_sha256"],"rust_archive_sha256":EXACT_ARCHIVE,"go_package_count":go_count,"rust_source_files":count,"rust_notice_files":old["rust_notice_files"],"go_notice_files":old["go_notice_files"],"mpl_archives":old["mpl_archives"],"remaining":["final product linkage and notice/source publication consent","opaque SDK terms and runtime privacy","production signed acceptance"],"files":{f.relative_to(p).as_posix():sha(f) for f in sorted(p.rglob("*")) if f.is_file()}}
        put(p/"manifest.json",(json.dumps(report,indent=2,sort_keys=True)+"\n").encode())
        for n,h in report["files"].items():checked(p,n,h)
        need(not out.exists(),"destination appeared");p.rename(out)
    return report

if __name__=="__main__":
    result=stage(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).absolute())
    print("PRIVATE_EXACT_REVIEW",len(result["files"]),result["go_package_count"],result["rust_source_files"],result["release_authorized"])
