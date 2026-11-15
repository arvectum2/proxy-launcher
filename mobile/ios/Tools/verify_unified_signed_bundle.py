#!/usr/bin/env python3
"""Read-only future signed QA bundle identity check; never signs or installs.
Expected record must be independently obtained from authorized signing/build.
It does not prove signed Mach-O equivalence with previous unsigned build.
"""
import datetime,hashlib,json,pathlib,plistlib,re,subprocess,sys
from unified_synthetic_fixture import CONTAINING_CANDIDATE,SPLIT_CANDIDATE
from validate_unified_synthetic_receipt import exact,need,read
BASE='ru.arvectum.proxylauncher.lab.productunifiedcompile'

def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def validate_record(r):
    exact(r,'schema candidateManifestSHA256 team device hostSHA256 extensionSHA256 hostInfoSHA256 extensionInfoSHA256')
    need(type(r['schema'])==int and r['schema']==1 and r['candidateManifestSHA256'] in (CONTAINING_CANDIDATE,SPLIT_CANDIDATE),'wrong candidate')
    need(type(r['team'])==str and re.fullmatch('[A-Z0-9]{10}',r['team']) and type(r['device'])==str and re.fullmatch('[0-9A-Fa-f-]{24,40}',r['device']),'invalid expected identity')
    for k in ('hostSHA256','extensionSHA256','hostInfoSHA256','extensionInfoSHA256'):need(type(r[k])==str and re.fullmatch('[a-f0-9]{64}',r[k]),'invalid expected hash')

def validate_scope(info,profile,actual,ident,team,device,now):
    need(info.get('CFBundleIdentifier')==ident and 'APLKeychainAccessGroup' not in info,'bundle scope mismatch')
    e=profile.get('Entitlements',{});app=team+'.'+ident
    expiry=profile.get('ExpirationDate');need(isinstance(expiry,datetime.datetime) and expiry.replace(tzinfo=datetime.timezone.utc)>now,'expired development profile')
    need(profile.get('TeamIdentifier')==[team] and device in profile.get('ProvisionedDevices',[]) and not profile.get('ProvisionsAllDevices'),'profile scope mismatch')
    for x in (e,actual):
        need(x.get('application-identifier')==app and x.get('com.apple.developer.team-identifier')==team and x.get('get-task-allow') is True,'development identity mismatch')
        need(x.get('com.apple.developer.networking.networkextension')==['packet-tunnel-provider'],'wrong network extension capability')
        need(not x.get('com.apple.security.application-groups') and not x.get('com.apple.developer.ubiquity-container-identifiers') and not x.get('com.apple.developer.icloud-container-identifiers') and not x.get('aps-environment'),'unexpected shared/account capability')
        need(all(g==app for g in x.get('keychain-access-groups',[])),'shared keychain capability')
    allowed={'application-identifier','com.apple.developer.team-identifier','get-task-allow','com.apple.developer.networking.networkextension','keychain-access-groups'}
    need(set(actual).issubset(allowed),'unexpected signed entitlement')
    if ident.endswith('.PacketTunnel'):need(info.get('NSExtension',{}).get('NSExtensionPointIdentifier')=='com.apple.networkextension.packet-tunnel','wrong extension point')

def verify_bundle(host,record):
    validate_record(record);need(host.is_dir() and not host.is_symlink(),'invalid bundle')
    need(all(not p.is_symlink() for p in host.rglob('*')),'symlink in isolated bundle')
    ext=host/'PlugIns/PacketTunnelCandidate.appex';need(ext.is_dir() and list((host/'PlugIns').iterdir())==[ext],'unexpected extensions')
    now=datetime.datetime.now(datetime.timezone.utc)
    for bundle,ident,prefix,exe in [(host,BASE,'host','UnifiedAcceptanceHost'),(ext,BASE+'.PacketTunnel','extension','PacketTunnelCandidate')]:
        info=bundle/'Info.plist';binary=bundle/exe;provision=bundle/'embedded.mobileprovision'
        need(all(x.is_file() and not x.is_symlink() for x in (info,binary,provision)),'signed bundle incomplete')
        need(sha(binary)==record[prefix+'SHA256'] and sha(info)==record[prefix+'InfoSHA256'],'expected signed build hash mismatch')
        subprocess.run(['codesign','--verify','--strict',str(bundle)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=20)
        actual=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(bundle)],stderr=subprocess.DEVNULL,timeout=10))
        profile=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(provision)],stderr=subprocess.DEVNULL,timeout=10))
        validate_scope(plistlib.loads(info.read_bytes()),profile,actual,ident,record['team'],record['device'],now)
    return {'status':'signed_identity_scope_verified_only','candidateManifestSHA256':record['candidateManifestSHA256'],'hostSHA256':record['hostSHA256'],'extensionSHA256':record['extensionSHA256'],'runtime_authorized':False,'release_authorized':False}

if __name__=='__main__':
    if len(sys.argv)!=4:raise SystemExit('usage: verify_unified_signed_bundle.py APP EXPECTED_PRIVATE_RECORD EXPECTED_RECORD_SHA256')
    host,expected=map(pathlib.Path,sys.argv[1:3]);need(sha(expected)==sys.argv[3],'trusted record digest mismatch');r=read(expected)
    print(json.dumps(verify_bundle(host,r),sort_keys=True))
