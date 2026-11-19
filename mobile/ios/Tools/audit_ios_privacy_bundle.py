#!/usr/bin/env python3
"""Inspect actual unsigned iOS bundle declarations, not runtime transfers."""
import hashlib,json,pathlib,plistlib,sys

def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def audit(app):
    if not app.is_dir() or app.is_symlink() or list(app.rglob('embedded.mobileprovision')):raise ValueError('unsigned local bundle required')
    info=plistlib.loads((app/'Info.plist').read_bytes());bundle=info['CFBundleIdentifier']
    if bundle!='ru.arvectum.proxylauncher.ios':raise ValueError('wrong app')
    exe=app/info['CFBundleExecutable'];rows=[]
    for p in sorted(app.rglob('PrivacyInfo.xcprivacy')):
        if p.is_symlink():raise ValueError('symlink manifest')
        d=plistlib.loads(p.read_bytes());rel=p.relative_to(app).as_posix()
        rows.append({'path':rel,'sha256':sha(p),'tracking':d.get('NSPrivacyTracking'),'tracking_domains':d.get('NSPrivacyTrackingDomains',[]),'collected_data':d.get('NSPrivacyCollectedDataTypes',[]),'accessed_api':d.get('NSPrivacyAccessedAPITypes',[])})
    by={r['path']:r for r in rows};ad=by['Frameworks/YandexMobileAds.framework/PrivacyInfo.xcprivacy'];support=by['AppMetrica_AppMetricaAdSupport.bundle/PrivacyInfo.xcprivacy'];app_decl=by['PrivacyInfo.xcprivacy'];provider='PlugIns/Arvectum Packet Tunnel.appex'
    if provider+'/PrivacyInfo.xcprivacy' not in by:raise ValueError('missing extension declaration')
    return {'schema':1,'scope':'static declarations from exact unsigned bundle; not evidence of actual collection, transmission, or compliance','bundle':bundle,'app_sha256':sha(exe),'provider_sha256':sha(app/provider/'Arvectum Packet Tunnel'),'ad_framework_sha256':sha(app/'Frameworks/YandexMobileAds.framework/YandexMobileAds'),'manifest_count':len(rows),'manifests':rows,'tracking_declared_by':[r['path'] for r in rows if r['tracking'] is True],'data_declared_by':[r['path'] for r in rows if r['collected_data']],'app_declares_no_collection':not app_decl['collected_data'],'ads_declares_collection':bool(ad['collected_data']),'appmetrica_adsupport_tracking':support['tracking'] is True,'runtime_authorized':False,'release_authorized':False}

if __name__=='__main__':
    if len(sys.argv)!=2:raise SystemExit('usage: audit_ios_privacy_bundle.py UNSIGNED_APP')
    print(json.dumps(audit(pathlib.Path(sys.argv[1])),indent=2,sort_keys=True))
