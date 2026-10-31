#!/usr/bin/env python3
"""Review-safe Apple version 0.1.41 plan; never touches submitted 0.1.40.

Default: offline plan. --live-check: read Apple versions/builds only.
--create --confirm-version 0.1.41: create an editable version ONLY after 0.1.40
becomes READY_FOR_SALE and 0.1.41 doesn't already exist.
"""
import argparse
import sys
from import_appstore import APP_ID, ASC, ImportErrorASC, payload

NEXT='0.1.41'
PREVIOUS='0.1.40'


def guard_create(versions):
    ios=[v for v in versions if v['attributes'].get('platform')=='IOS']
    matches=[v for v in ios if v['attributes'].get('versionString')==NEXT]
    if matches:
        return matches[0]['id'], 'EXISTS'
    prev=[v for v in ios if v['attributes'].get('versionString')==PREVIOUS]
    if len(prev)!=1:
        raise ImportErrorASC('Cannot uniquely identify iOS '+PREVIOUS)
    state=prev[0]['attributes']['appStoreState']
    if state!='READY_FOR_SALE':
        raise ImportErrorASC('Creation blocked: 0.1.40 is '+state+'; current Apple review is preserved')
    return None, 'CAN_CREATE'


def build_payload(previous):
    attributes={'platform':'IOS','versionString':NEXT}
    # Mirror the previous app's actual release policy, not guesses.
    for key in ('copyright','releaseType'):
        if previous['attributes'].get(key) is not None:
            attributes[key]=previous['attributes'][key]
    return payload('appStoreVersions',attributes,relation=('app','apps',APP_ID))


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live-check',action='store_true')
    parser.add_argument('--create',action='store_true')
    parser.add_argument('--confirm-version')
    args=parser.parse_args(argv)
    if args.create and args.confirm_version!=NEXT:
        parser.error('Creating a version requires --confirm-version '+NEXT)
    if not args.live_check and not args.create:
        print('OFFLINE_PLAN next=0.1.41 minimum_build=46 previous=0.1.40 apple_mutations=0')
        return 0
    api=ASC()
    versions=api.list(f'/apps/{APP_ID}/appStoreVersions?limit=100')
    try:
        version_id, status=guard_create(versions)
    except ImportErrorASC as exc:
        print('NOT_READY',str(exc))
        if args.create:raise
        return 0
    print('NEXT_VERSION',NEXT,status,version_id or '-',flush=True)
    if not args.create:
        print('READ_ONLY: NO_APP_STORE_WRITES')
        return 0
    if status=='EXISTS':
        print('NO_DUPLICATE_CREATED',version_id)
        return 0
    previous=next(v for v in versions if v['attributes'].get('platform')=='IOS' and v['attributes'].get('versionString')==PREVIOUS)
    # Fresh GET immediately before external side effect, fail closed if state moved.
    fresh=api.call('GET',f'/appStoreVersions/{previous["id"]}')['data']
    guard_create([fresh])
    response=api.call('POST','/appStoreVersions',build_payload(fresh))
    created=response['data']
    if created['attributes']['versionString']!=NEXT or created['attributes']['appStoreState']!='PREPARE_FOR_SUBMISSION':
        raise ImportErrorASC('Apple created unexpected version state; inspect it before proceeding')
    print('VERSION_CREATED',NEXT,created['id'])
    return 0

if __name__=='__main__':
    try:sys.exit(main())
    except ImportErrorASC as exc:
        print('VERSION_PREPARATION_BLOCKED',exc,file=sys.stderr)
        sys.exit(2)
