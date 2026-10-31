#!/usr/bin/env python3
"""Verify and submit ONLY iOS 0.1.41 to App Review after all assets pass.

This tool cannot cancel/modify an older review or Apple privacy disclosures.
Without --submit --confirm-version 0.1.41, it performs read-only checks.
"""
import argparse
import sys
from import_appstore import ASC, APP_ID, ImportErrorASC, load_rows, existing_version, verify_asset_processing
from upload_release_041 import candidate, DEFAULT_ASSET, find_processed_build

VERSION = '0.1.41'


def readiness(api, require_assets=True):
    v = existing_version(api, VERSION)
    state = v['attributes']['appStoreState']
    if state not in ('PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW'):
        raise ImportErrorASC(f'iOS {VERSION} unexpected state: {state}')
    rows = load_rows()
    required = {r['locale'] for r in rows}
    locs = api.list(f'/appStoreVersions/{v["id"]}/appStoreVersionLocalizations?limit=200')
    absent = sorted(required - {x['attributes']['locale'] for x in locs})
    if absent:
        raise ImportErrorASC(f'Missing {len(absent)} version ASO locales: {absent[:8]}')
    app_infos = api.list(f'/apps/{APP_ID}/appInfos?limit=100')
    active = [x for x in app_infos if x['attributes'].get('appStoreState') == 'PREPARE_FOR_SUBMISSION']
    if len(active) != 1:
        raise ImportErrorASC(f'Expected one editable appInfo, got {len(active)}')
    info_loc = api.list(f'/appInfos/{active[0]["id"]}/appInfoLocalizations?limit=200')
    missing_info = sorted(required - {x['attributes']['locale'] for x in info_loc})
    if missing_info:
        raise ImportErrorASC(f'Missing app-info locales: {missing_info[:8]}')
    if require_assets:
        verify_asset_processing(api, v['id'], rows)
    build = find_processed_build(api)
    rel = api.call('GET', f'/appStoreVersions/{v["id"]}?include=build')['data']
    attached = (rel.get('relationships', {}).get('build', {}) or {}).get('data')
    if not attached or attached.get('id') != build['id']:
        raise ImportErrorASC(f'Build 46 is not attached to iOS {VERSION}')
    print('READY_FOR_SUBMISSION',VERSION,'LOCALES',len(required),'IMAGES',2*len(required),
          'BUILD',build['id'],'STATE',state, flush=True)
    return v


def existing_draft(api):
    submissions = api.list(f'/apps/{APP_ID}/reviewSubmissions?limit=100')
    drafts = [s for s in submissions if s['attributes'].get('platform') == 'IOS'
              and s['attributes'].get('state') == 'READY_FOR_REVIEW']
    if len(drafts) > 1:
        raise ImportErrorASC('Multiple iOS review drafts: select the correct one manually')
    return drafts[0] if drafts else None


def send(api, version):
    draft = existing_draft(api)
    if draft is None:
        draft = api.call('POST','/reviewSubmissions',{
            'data': {'type':'reviewSubmissions',
                     'attributes': {'platform':'IOS'},
                     'relationships': {'app': {'data': {'type':'apps', 'id':APP_ID}}}}
        })['data']
        print('REVIEW_DRAFT_CREATED',draft['id'],flush=True)
    else:
        print('EXISTING_REVIEW_DRAFT',draft['id'],flush=True)
    items = api.list(f'/reviewSubmissions/{draft["id"]}/items?limit=100')
    if len(items) > 1:
        raise ImportErrorASC('Unexpected unrelated review items; refusing to submit')
    if not items:
        item = api.call('POST','/reviewSubmissionItems',{
            'data': {'type':'reviewSubmissionItems',
                     'relationships': {
                         'reviewSubmission': {'data': {'type':'reviewSubmissions','id':draft['id']}},
                         'appStoreVersion': {'data': {'type':'appStoreVersions','id':version['id']}}
                     }}
        })['data']
        print('REVIEW_ITEM_CREATED',item['id'],flush=True)
    else:
        # Do not blindly reuse unrelated draft items.
        details = api.call('GET',f'/reviewSubmissionItems/{items[0]["id"]}?include=appStoreVersion')
        rel = (details['data'].get('relationships',{}).get('appStoreVersion',{}) or {}).get('data')
        if rel is None or rel.get('id') != version['id']:
            raise ImportErrorASC('Draft contains a different version: stop before submit')
    new_version = existing_version(api,VERSION)
    if new_version['attributes']['appStoreState'] not in ('PREPARE_FOR_SUBMISSION','READY_FOR_REVIEW'):
        raise ImportErrorASC('State changed before Apple submit')
    response = api.call('PATCH', f'/reviewSubmissions/{draft["id"]}',{
        'data': {'type':'reviewSubmissions','id':draft['id'],
                 'attributes': {'submitted':True}}
    })['data']
    print('APPLE_SUBMISSION_RESULT',draft['id'],response['attributes'].get('state'),flush=True)
    return response


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--submit',action='store_true',help='Submit the reviewed app version to Apple')
    p.add_argument('--confirm-version',help='Must equal 0.1.41 for submission')
    args=p.parse_args(argv)
    if args.submit and args.confirm_version != VERSION:
        p.error('Submission requires --confirm-version 0.1.41')
    api=ASC()
    version=readiness(api)
    if not args.submit:
        print('READ_ONLY_READY; no review created or submitted')
        return 0
    send(api,version)
    return 0


if __name__=='__main__':
    try:
        sys.exit(main())
    except ImportErrorASC as ex:
        print('RELEASE_SUBMISSION_BLOCKED',str(ex),file=sys.stderr)
        sys.exit(2)
