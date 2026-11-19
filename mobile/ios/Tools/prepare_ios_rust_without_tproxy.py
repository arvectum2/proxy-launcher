#!/usr/bin/env python3
"""Prepare a separate locked source candidate; never install/promote a build."""
import hashlib,json,pathlib,shutil,subprocess,sys,tomllib
import fetch_tun2proxy as pin
T=pathlib.Path(__file__).resolve().parent

def run(args,cwd=None):return subprocess.check_output(args,cwd=cwd,text=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def replace(p,old,new):
    s=p.read_text();assert s.count(old)==1,(p,old);p.write_text(s.replace(old,new,1))

def prepare(source,work):
    assert run(['git','-C',str(source),'rev-parse','HEAD']).strip()==pin.SOURCE_COMMIT
    assert not run(['git','-C',str(source),'status','--porcelain']).strip()
    work.mkdir(mode=0o700);archive=work/'source.tar';src=work/'src';src.mkdir()
    subprocess.run(['git','-C',str(source),'archive','--format=tar','-o',str(archive),pin.SOURCE_COMMIT],check=True)
    subprocess.run(['tar','-xf',str(archive),'-C',str(src)],check=True);archive.unlink()
    shutil.copy2(pin.LOCKFILE,src/'Cargo.lock');replace(src/'src/general_api.rs',pin.FORCED_EXIT_BLOCK,pin.PATCHED_BLOCK)
    patches=[pin.SPLIT_DNS_PATCH,pin.FLOW_INTENT_PATCH,pin.SCOPED_DIRECT_EXPERIMENT_PATCH,pin.SAME_FLOW_RETRY_PATCH,pin.DIRECT_FAMILY_PATCH,T/'NativeTunnelLab/tun2proxy-connected-udp-loopback-clean.patch']
    for p in patches:subprocess.run(['git','apply','--check',str(p)],cwd=src,check=True);subprocess.run(['git','apply',str(p)],cwd=src,check=True)
    cargo=src/'Cargo.toml';replace(cargo,'tproxy-config = { version = "^7.0.7", default-features = false }\n','cidr = { version = "=0.3.2", features = ["serde"] }\n')
    with cargo.open('a') as f:f.write('\n[target.\'cfg(not(target_os="ios"))\'.dependencies]\ntproxy-config = { version = "^7.0.7", default-features = false }\n')
    for p in (src/'src').rglob('*.rs'):
        s=p.read_text()
        if 'use tproxy_config::IpCidr;' in s:p.write_text(s.replace('use tproxy_config::IpCidr;','use cidr::IpCidr;'))
    replace(src/'src/lib.rs','use tproxy_config::is_private_ip;','#[cfg(not(target_os = "ios"))]\nuse tproxy_config::is_private_ip;\n#[cfg(target_os = "ios")]\nmod ios_dns_address_classification;\n#[cfg(target_os = "ios")]\nuse ios_dns_address_classification::is_private_ip;')
    helper=T/'NativeTunnelLab/ios_dns_address_classification.rs';shutil.copy2(helper,src/'src/ios_dns_address_classification.rs')
    cmd=['cargo','+1.98.1'];run(cmd+['metadata','--offline','--filter-platform','aarch64-apple-ios','--format-version','1'],src)
    old=tomllib.loads(pin.LOCKFILE.read_text());new=tomllib.loads((src/'Cargo.lock').read_text())
    key=lambda p:(p['name'],p['version'],p.get('source'),p.get('checksum'))
    assert {key(p) for p in new['package']}=={key(p) for p in old['package']},'unexpected resolution change'
    for target in ('aarch64-apple-ios','aarch64-apple-ios-sim'):
        tree=run(cmd+['tree','--offline','--locked','--target',target,'--edges','normal,build','--prefix','none','--format','{p}'],src)
        assert 'tproxy-config v' not in tree and 'cidr v0.3.2' in tree
        (work/(target+'.tree')).write_text(tree)
    (work/'preparation.json').write_text(json.dumps({'schema':1,'source_commit':pin.SOURCE_COMMIT,'toolchain':'1.98.1','original_lock_sha256':sha(pin.LOCKFILE),'candidate_lock_sha256':sha(src/'Cargo.lock'),'patches':{p.name:sha(p) for p in patches},'helper_sha256':sha(helper),'runtime_authorized':False,'release_authorized':False},indent=2)+'\n')
    print('IOS_TARGET_GRAPH_WITHOUT_TPROXY_PASS')

if __name__=='__main__':prepare(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]))
