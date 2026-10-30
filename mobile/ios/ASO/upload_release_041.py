#!/usr/bin/env python3
"""Review-safe upload/attach for the locally signed 0.1.41(46) IPA.

Default: OFFLINE. --live-check uses Apple GET only. Explicit --upload and
--attach must be separately confirmed and require 0.1.40 READY_FOR_SALE.
Never submits to App Review or changes live 0.1.40/privacy metadata.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from import_appstore import ASC, APP_ID, ImportErrorASC, assert_editable, assert_predecessor_released, existing_version

DEFAULT_ASSET=Path('/Volumes/ArvectumSSD/Arvectum/releases/APL-iOS-0.1.41-46-homefit-final-20261030')
VERSION='0.1.41'
BUILD='46'


def candidate(folder):
    manifest=json.loads((folder/'candidate-manifest.json').read_text(encoding='utf-8'))
    if manifest.get('version')!=VERSION or str(manifest.get('build'))!=BUILD:
        raise ImportErrorASC('Wrong iOS version/build in local release manifest')
    ipa=Path(manifest['ipa'])
    if not ipa.is_file() or not ipa.is_relative_to(folder):
        raise ImportErrorASC('IPA must exist inside verified release output directory')
    checksum=hashlib.sha256(ipa.read_bytes()).hexdigest()
    if checksum!=manifest['sha256'] or manifest['iosLocalizations']!=50 or manifest['packetTunnelExtensions']!=1:
        raise ImportErrorASC('Signed candidate IPA integrity failed')
    return manifest,ipa


def check_release(api,version):
    assert_predecessor_released(api)
    target=existing_version(api,version)
    assert_editable(target)
    return target


def find_processed_build(api):
    matches=[x for x in api.list('/builds?filter%5Bapp%5D='+APP_ID+'&limit=100')
             if x['attributes'].get('version')==BUILD]
    if len(matches)!=1:
        raise ImportErrorASC('Need exactly one uploaded Apple build '+BUILD+'; found '+str(len(matches)))
    item=matches[0]
    if item['attributes'].get('processingState')!='VALID':
        raise ImportErrorASC('Apple build 46 processing not finished: '+str(item['attributes'].get('processingState')))
    pre=api.call('GET',f'/builds/{item["id"]}/preReleaseVersion')['data']
    if pre['attributes']['version']!=VERSION:
        raise ImportErrorASC('Build 46 belongs to app version '+str(pre['attributes']['version']))
    return item


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release-dir',type=Path,default=DEFAULT_ASSET)
    parser.add_argument('--live-check',action='store_true')
    parser.add_argument('--upload',action='store_true')
    parser.add_argument('--attach',action='store_true')
    parser.add_argument('--confirm-version')
    args=parser.parse_args(argv)
    if args.upload and args.attach:
        parser.error('Upload and attach are separate deliberate operations')
    if (args.upload or args.attach) and args.confirm_version!=VERSION:
        parser.error('Writing requires --confirm-version 0.1.41')
    manifest,ipa=candidate(args.release_dir.resolve())
    if not (args.upload or args.attach or args.live_check):
        print('OFFLINE_IPA',str(ipa),'SHA256',manifest['sha256'],'APPLE_WRITES',0)
        return 0
    api=ASC()
    if not args.upload and not args.attach:
        prev=existing_version(api,'0.1.40')
        print('PREVIOUS',prev['attributes']['appStoreState'])
        try:target=existing_version(api,VERSION)
        except ImportErrorASC:print('NEXT',VERSION,'NOT_YET_CREATED')
        else:print('NEXT',VERSION,target['attributes']['appStoreState'])
        print('READ_ONLY: NO_APP_STORE_WRITES')
        return 0
    target=check_release(api,VERSION)
    if args.upload:
        uploaded=[x for x in api.list('/builds?filter%5Bapp%5D='+APP_ID+'&limit=100')
                  if x['attributes'].get('version')==BUILD]
        if uploaded:
            # An in-progress or failed processing state is NOT permission to
            # re-upload the same build number. Never duplicate an Apple build.
            if len(uploaded)!=1:raise ImportErrorASC('Ambiguous Apple build number 46')
            item=uploaded[0]
            prerelease=api.call('GET',f'/builds/{item["id"]}/preReleaseVersion')['data']
            if prerelease['attributes']['version']!=VERSION:
                raise ImportErrorASC('Apple build number 46 belongs to another app version')
            print('BUILD_ALREADY_IN_APPLE',item['id'],item['attributes']['processingState'])
            return 0
        # Upload the signed IPA to Apple's processing queue, not App Review.
        r=subprocess.run([api.altool,'--upload-app','--file',str(ipa),'--type','ios',
                          '--apiKey',api.env['ASC_KEY_ID'],'--apiIssuer',api.env['ASC_ISSUER_ID']],
                          env=api.env,capture_output=True,text=True,timeout=900)
        if r.returncode:
            raise ImportErrorASC('altool upload failed; inspect local Xcode delivery logs: '+r.stderr[-450:])
        print('IPA_DELIVERED_FOR_APPLE_PROCESSING',VERSION,BUILD)
        return 0
    item=find_processed_build(api)
    target=check_release(api,VERSION)
    app_version=api.call('GET',f'/appStoreVersions/{target["id"]}?include=build')['data']
    current=app_version.get('relationships',{}).get('build',{}).get('data')
    if current:
        if current['id']!=item['id']:
            raise ImportErrorASC('0.1.41 has a different attached build; refusing replacement')
        print('BUILD_ALREADY_ATTACHED',item['id'])
        return 0
    api.call('PATCH',f'/appStoreVersions/{target["id"]}/relationships/build',
             {'data':{'type':'builds','id':item['id']}})
    print('BUILD_ATTACHED',VERSION,BUILD,item['id'])
    return 0

if __name__=='__main__':
    try:sys.exit(main())
    except ImportErrorASC as error:
        print('RELEASE_041_BLOCKED',error,file=sys.stderr)
        sys.exit(2)
