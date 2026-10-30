#!/usr/bin/env python3
"""iOS ASO import. Default: offline plan; --live-check: Apple GET only.

--execute requires exact version confirmation and an editable Apple version.
Never withdraws an app from review, edits the privacy questionnaire, or uploads binaries.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
BASE = 'https://api.appstoreconnect.apple.com/v1'
APP_ID = '6816013574'
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'METADATA_REJECTED', 'REJECTED', 'INVALID_BINARY'}
SCREEN_TYPE = 'APP_IPHONE_61'
PREVIOUS_VERSION = '0.1.40'
TARGET_VERSION = '0.1.41'

class ImportErrorASC(Exception):
    pass

def payload(kind, attrs, id=None, relation=None):
    data = {'type': kind, 'attributes': attrs}
    if id:
        data['id'] = id
    if relation:
        key, other_type, other_id = relation
        data['relationships'] = {key: {'data': {'type': other_type, 'id': other_id}}}
    return {'data': data}

def load_rows():
    rows = json.loads((ROOT/'localizations.json').read_text(encoding='utf-8'))['localizations']
    assert len(rows) == 47
    for row in rows:
        assert len(row['name']) <= 30 and len(row['subtitle']) <= 30
        assert len(row['keywords'].encode('utf-8')) <= 100
        for name in ('01-first-connection.jpg','02-local-privacy.jpg'):
            assert (ROOT/'screenshots'/row['locale']/name).is_file(), row['locale']
    return rows

class ASC:
    def __init__(self):
        config = Path.home()/'.config/arvectum/appstore-connect.env'
        assert config.is_file(), 'Apple environment not configured'
        output = subprocess.check_output(['/bin/zsh','-c','set -a; source "$1"; env -0','zsh',str(config)])
        env = dict(v.split('=',1) for v in output.decode().split('\0') if '=' in v)
        self.env = {**os.environ, **env}
        self.env['API_PRIVATE_KEYS_DIR'] = env.get('ASC_KEY_DIR',str(Path.home()/'.appstoreconnect/private_keys'))
        self.altool = env.get('ASC_ALTOOL','/Volumes/ArvectumSSD/Arvectum/DevTools/Xcodes/Xcode-27.1.0.app/Contents/SharedFrameworks/ContentDelivery.framework/Versions/A/Resources/altool')
        self.token = None
        self.issued = 0

    def jwt(self):
        if not self.token or time.monotonic() - self.issued > 720:
            run = subprocess.run([self.altool,'--generate-jwt','--apiKey',self.env['ASC_KEY_ID'],'--apiIssuer',self.env['ASC_ISSUER_ID']],env=self.env,capture_output=True,text=True,check=True,timeout=30)
            match = re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',run.stdout+'\n'+run.stderr)
            if not match: raise ImportErrorASC('Cannot generate Apple JWT')
            self.token = match.group(0)
            self.issued = time.monotonic()
        return self.token

    def call(self, method, path, data=None):
        assert path.startswith('/') and '://' not in path
        body = json.dumps(data,ensure_ascii=False).encode('utf-8') if data is not None else None
        for attempt in range(3):
            request = Request(BASE+path,data=body,method=method,headers={'Authorization':'Bearer '+self.jwt(),'Accept':'application/json','Content-Type':'application/json'})
            try:
                with urlopen(request,timeout=45) as response:
                    raw = response.read()
                    return json.loads(raw) if raw else {}
            except HTTPError as err:
                message = err.read(300).decode('utf-8','replace')
                if attempt < 2 and err.code in (429,500,502,503,504):
                    time.sleep(2**(attempt+1))
                    continue
                raise ImportErrorASC(f'Apple API HTTP {err.code} {method} {path}: {message}') from None

    def list(self, path):
        result=[]
        while path:
            d=self.call('GET',path)
            result+=d.get('data',[])
            link=d.get('links',{}).get('next')
            if link and not link.startswith(BASE): raise ImportErrorASC('Unexpected API pagination URL')
            path=link[len(BASE):] if link else None
        return result

def existing_version(api, version_name):
    versions=api.list(f'/apps/{APP_ID}/appStoreVersions?limit=100')
    items=[x for x in versions if x['attributes'].get('platform')=='IOS' and x['attributes'].get('versionString')==version_name]
    if len(items)!=1: raise ImportErrorASC(f'Expected one existing iOS version {version_name}; found {len(items)}')
    return items[0]

def assert_editable(version):
    state=version['attributes']['appStoreState']
    if state not in EDITABLE:
        raise ImportErrorASC(f'BLOCKED: Apple iOS {version["attributes"]["versionString"]} is {state}. No App Store mutations allowed while under review.')

def assert_predecessor_released(api):
    previous=existing_version(api, PREVIOUS_VERSION)
    if previous['attributes']['appStoreState']!='READY_FOR_SALE':
        raise ImportErrorASC('Current 0.1.40 review is not finished; it remains protected')

def matching_appinfo(api, state):
    infos=api.list(f'/apps/{APP_ID}/appInfos?limit=100')
    eligible=[x for x in infos if x['attributes'].get('appStoreState')==state]
    if len(eligible)!=1: raise ImportErrorASC(f'Cannot uniquely locate editable appInfo for {state}')
    return eligible[0]['id']

def upsert(api, kind, attrs, existing, relation):
    if existing:
        return api.call('PATCH',f'/{kind}/{existing}',payload(kind,attrs,existing))['data']
    return api.call('POST',f'/{kind}',payload(kind,attrs,relation=relation))['data']

def upload_image(api, set_id, path):
    content=path.read_bytes()
    result=api.call('POST','/appScreenshots',payload('appScreenshots',{'fileName':path.name,'fileSize':len(content)},relation=('appScreenshotSet','appScreenshotSets',set_id)))['data']
    for op in result['attributes']['uploadOperations']:
        offset,length=int(op['offset']),int(op['length'])
        assert 0 <= offset <= offset+length <= len(content)
        assert op['url'].startswith('https://')
        headers={h['name']:h['value'] for h in op.get('requestHeaders',[])}
        request=Request(op['url'],data=content[offset:offset+length],method=op['method'],headers=headers)
        with urlopen(request,timeout=90) as uploaded:
            if uploaded.status not in (200,201,202,204): raise ImportErrorASC('Unexpected screenshot upload status')
    api.call('PATCH',f'/appScreenshots/{result["id"]}',payload('appScreenshots',{'uploaded':True,'sourceFileChecksum':hashlib.md5(content).hexdigest()},result['id']))
    return result['id']

def upsert_locale(api, version_id, info_id, row):
    lang=row['locale']
    infos={x['attributes']['locale']:x for x in api.list(f'/appInfos/{info_id}/appInfoLocalizations?limit=200')}
    vers={x['attributes']['locale']:x for x in api.list(f'/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=200')}
    info={'name':row['name'],'subtitle':row['subtitle']}
    localized={k:row[k] for k in ('description','keywords','promotionalText','whatsNew','supportUrl','marketingUrl')}
    if lang not in infos: info['locale']=lang
    if lang not in vers: localized['locale']=lang
    upsert(api,'appInfoLocalizations',info,infos[lang]['id'] if lang in infos else None,('appInfo','appInfos',info_id))
    version=upsert(api,'appStoreVersionLocalizations',localized,vers[lang]['id'] if lang in vers else None,('appStoreVersion','appStoreVersions',version_id))
    sets=api.list(f'/appStoreVersionLocalizations/{version["id"]}/appScreenshotSets?limit=100')
    target=next((x for x in sets if x['attributes']['screenshotDisplayType']==SCREEN_TYPE),None)
    if not target:
        target=api.call('POST','/appScreenshotSets',payload('appScreenshotSets',{'screenshotDisplayType':SCREEN_TYPE},relation=('appStoreVersionLocalization','appStoreVersionLocalizations',version['id'])))['data']
    screenshots={x['attributes'].get('fileName'):x for x in api.list(f'/appScreenshotSets/{target["id"]}/appScreenshots?limit=100')}
    for name in ('01-first-connection.jpg','02-local-privacy.jpg'):
        if name in screenshots:
            print('EXISTS_IMAGE',lang,name,flush=True)
        else:
            ident=upload_image(api,target['id'],ROOT/'screenshots'/lang/name)
            print('UPLOADED_IMAGE',lang,name,ident,flush=True)

def verify_asset_processing(api, version_id, rows):
    """Read-only: require Apple to report COMPLETE, not just uploaded bytes."""
    available = {x['attributes']['locale']: x for x in api.list(
        f'/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=200')}
    errors=[]
    for row in rows:
        locale=row['locale']
        entry=available.get(locale)
        if entry is None:
            errors.append((locale,'missing localization'))
            continue
        sets=api.list(f'/appStoreVersionLocalizations/{entry["id"]}/appScreenshotSets?limit=100')
        target=next((x for x in sets if x['attributes']['screenshotDisplayType']==SCREEN_TYPE),None)
        if target is None:
            errors.append((locale,'missing iPhone screenshots'))
            continue
        shots={x['attributes'].get('fileName'):x for x in api.list(
            f'/appScreenshotSets/{target["id"]}/appScreenshots?limit=100')}
        for file in ('01-first-connection.jpg','02-local-privacy.jpg'):
            item=shots.get(file)
            if not item:
                errors.append((locale,file,'missing image'))
                continue
            source=ROOT/'screenshots'/locale/file
            expected=hashlib.md5(source.read_bytes()).hexdigest()
            got=(item['attributes'].get('sourceFileChecksum') or '').lower()
            state=item['attributes'].get('assetDeliveryState') or {}
            state=state.get('state') if isinstance(state,dict) else state
            if state!='COMPLETE' or got!=expected:
                errors.append((locale,file,'state '+str(state),'checksum matches '+str(got==expected)))
    if errors:
        raise ImportErrorASC('Apple image verification incomplete: '+repr(errors[:8])+
                             f' ({len(errors)} incomplete assets)')
    print('ASSET_VERIFICATION_PASS',len(rows),'LOCALES',2*len(rows),'PROCESSED_IMAGES')


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',help='Existing App Store Connect iOS version')
    parser.add_argument('--live-check',action='store_true',help='Read-only query Apple state and locale counts')
    parser.add_argument('--execute',action='store_true',help='Import to an EDITABLE version only')
    parser.add_argument('--confirm-version',help='Mandatory exact --version repeat for any write')
    parser.add_argument('--only-locale',help='Stage one Apple locale first to verify API image uploads')
    parser.add_argument('--verify-only',action='store_true',help='Read-only processing/MD5 verification of Apple screenshots')
    args=parser.parse_args(argv)
    rows=load_rows()
    if not args.live_check and not args.execute and not args.verify_only:
        print('DRY_RUN ASO_LOCALES',len(rows),'SCREENSHOTS',len(rows)*2,'WRITE_OPERATIONS',0)
        print('SUPPORTED_APP_STORE_LOCALES',','.join(r['locale'] for r in rows))
        return 0
    if not args.version: parser.error('Specify --version')
    if args.execute and args.verify_only:parser.error('Choose either --execute or --verify-only')
    if args.execute and args.confirm_version != args.version:
        parser.error('Writing requires --confirm-version equal to --version')
    if args.execute and args.version != TARGET_VERSION:
        parser.error('Write scope is strictly limited to future iOS 0.1.41')
    if args.only_locale:
        rows = [row for row in rows if row['locale']==args.only_locale]
        if len(rows)!=1:parser.error('Unknown Apple locale: '+args.only_locale)
    api=ASC()
    version=existing_version(api,args.version)
    localizations=api.list(f'/appStoreVersions/{version["id"]}/appStoreVersionLocalizations?limit=200')
    print('APP_STORE_STATE',args.version,version['attributes']['appStoreState'],'LOCALES',len(localizations),flush=True)
    if args.verify_only:
        verify_asset_processing(api,version['id'],rows)
        print('READ_ONLY: NO_APP_STORE_WRITES')
        return 0
    if not args.execute:
        print('READ_ONLY: NO_APP_STORE_WRITES')
        return 0
    assert_editable(version)
    assert_predecessor_released(api)
    appinfo=matching_appinfo(api,version['attributes']['appStoreState'])
    for row in rows:
        # Fail before each locale if Apple state changed during a long upload.
        assert_editable(api.call('GET',f'/appStoreVersions/{version["id"]}')['data'])
        print('IMPORTING_LOCALE',row['locale'],flush=True)
        upsert_locale(api,version['id'],appinfo,row)
    actual=api.list(f'/appStoreVersions/{version["id"]}/appStoreVersionLocalizations?limit=200')
    if not {r['locale'] for r in rows}.issubset({x['attributes']['locale'] for x in actual}):
        raise ImportErrorASC('Some App Store localizations are missing after import')
    print('LOCALE_METADATA_IMPORTED',len(rows),'APP_STORE_LOCALES')
    verify_asset_processing(api,version['id'],rows)
    return 0

if __name__=='__main__':
    try:
        sys.exit(main())
    except ImportErrorASC as exc:
        print('IMPORT_STOPPED',str(exc),file=sys.stderr)
        sys.exit(2)
