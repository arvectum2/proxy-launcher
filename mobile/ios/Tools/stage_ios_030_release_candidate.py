#!/usr/bin/env python3
"""Stage an immutable, unsigned ARM64 Release candidate; no signing or install."""
import argparse, json, pathlib, shutil, subprocess, sys
from verify_ios_no_tproxy_receipt import sha, verify as stage_no_tproxy
from verify_ios_native_exact_dns_receipt import verify as stage_exact_dns

GO_RECEIPT = '1c8f00a729dac97e7670b718d6208d8e67946ea9b2260a9f68eed4a9fa5e0c54'
APP_FLAGS = 'APL_NATIVE_PROVIDER_INTEGRATION APL_NATIVE_PERSISTENT_LIBRARY APL_NATIVE_PRODUCT_RUNTIME APL_NATIVE_EXACT_DNS'
TUN_FLAGS = 'APL_NATIVE_PROVIDER_INTEGRATION APL_NATIVE_PRODUCT_RUNTIME APL_NATIVE_EXACT_DNS APL_NATIVE_XRAY_CANDIDATE APL_NATIVE_AWG_CANDIDATE APL_NATIVE_UNIFIED_GO_CANDIDATE APL_NATIVE_AWG_PRODUCT_BRIDGE'

def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('go', 'rust_framework', 'no_tproxy', 'exact_dns', 'out'):
        parser.add_argument(name, type=pathlib.Path)
    a = parser.parse_args()
    repo = pathlib.Path(subprocess.check_output(['git','rev-parse','--show-toplevel'], text=True).strip())
    commit = subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'], text=True).strip()
    assert not subprocess.check_output(['git','-C',str(repo),'status','--porcelain'])
    assert sha(a.go/'manifest.json') == GO_RECEIPT
    m = json.loads((a.go/'manifest.json').read_text())
    assert not m['release_authorized'] and not m['runtime_authorized']
    assert set(m['exports']) == {'CGoInvoke','CGoFree','aplAWGProductPrepare','aplAWGProductStart','aplAWGProductPush','aplAWGProductPull','aplAWGProductStop'}
    for n,h in m['files'].items():
        f = a.go/n
        assert f.resolve().is_relative_to(a.go.resolve()) and sha(f) == h
    assert sha(a.go/'libAPLUnified.a') == m['archive_sha256']
    a.out.mkdir(mode=0o700,parents=False,exist_ok=False)
    archive = subprocess.check_output(['git','-C',str(repo),'archive',commit,'mobile/ios'])
    run('tar','-xf','-','-C',str(a.out),input=archive)
    p = a.out/'mobile/ios'
    lib = p/'Lib/Unified'; headers = lib/'Headers'; headers.mkdir(parents=True)
    shutil.copyfile(a.go/'libAPLUnified.a',lib/'libAPLUnified.a')
    shutil.copyfile(a.go/'libAPLUnified.h',headers/'libAPLUnified.h')
    (headers/'module.modulemap').write_text('module APLUnifiedGo { header "libAPLUnified.h" export * }\n')
    run(sys.executable,str(p/'Tools/verify_tun2proxy_lab_artifact.py'),str(a.rust_framework),'ios-arm64','--require-connected-udp')
    framework = p/'Frameworks/tun2proxy.xcframework'; framework.parent.mkdir(exist_ok=True)
    shutil.copytree(a.rust_framework,framework)
    stage_no_tproxy(a.no_tproxy,framework/'ios-arm64')
    stage_exact_dns(a.exact_dns,framework/'ios-arm64',p)
    path=p/'project.yml'; s=path.read_text()
    assert s.count('MARKETING_VERSION: "0.2.0"')==1 and s.count('CURRENT_PROJECT_VERSION: "48"')==1
    s=s.replace('MARKETING_VERSION: "0.2.0"','MARKETING_VERSION: "0.3.0"').replace('CURRENT_PROJECT_VERSION: "48"','CURRENT_PROJECT_VERSION: "49"')
    for target,flags in [('ArvectumProxyLauncher',APP_FLAGS),('PacketTunnel',TUN_FLAGS)]:
        start=s.index('  '+target+':\n',s.index('targets:\n'))
        offset=s.index('        Release:\n',start)+len('        Release:\n')
        settings='          SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) '+flags+'"\n'
        if target=='PacketTunnel':
            settings+='          SWIFT_INCLUDE_PATHS: "$(PROJECT_DIR)/Lib/Unified/Headers"\n          LIBRARY_SEARCH_PATHS: "$(PROJECT_DIR)/Lib/Unified"\n          OTHER_LDFLAGS: "$(inherited) -lAPLUnified -lresolv"\n'
        s=s[:offset]+settings+s[offset:]
    assert not any(x in s for x in ('APL_NATIVE_SYNTHETIC_RUNTIME','APL_NATIVE_RUNTIME_QA_HARNESS','APL_NATIVE_RUNTIME_QA_DIAGNOSTICS','APL_NATIVE_PRODUCT_RUNTIME_REVIEW','APL_NATIVE_RELEASE_LINK_PREPARATION'))
    path.write_text(s)
    lock='ArvectumProxyLauncherIOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    locked=subprocess.check_output(['git','-C',str(repo),'show',commit+':mobile/ios/'+lock])
    run('xcodegen','generate',cwd=p)
    (p/lock).parent.mkdir(parents=True,exist_ok=True); (p/lock).write_bytes(locked)
    receipt={'source_commit':commit,'version':'0.3.0','build':'49','configuration':'Release','app_flags':APP_FLAGS,'provider_flags':TUN_FLAGS,'source_project_sha256':sha(path),'go_receipt_sha256':GO_RECEIPT,'go_archive_sha256':sha(lib/'libAPLUnified.a'),'rust_archive_sha256':sha(framework/'ios-arm64/libtun2proxy.a'),'package_lock_sha256':sha(p/lock),'compiled':False,'signed':False,'release_authorized':False}
    (a.out/'stage-manifest.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print('RELEASE_CANDIDATE_STAGED',commit,a.out)

if __name__=='__main__':main()
