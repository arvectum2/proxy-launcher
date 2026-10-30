#!/usr/bin/env python3
"""Build a local signed iOS 0.1.41 (46) candidate without modifying the checkout or ASC.

Requires Xcode, XcodeGen, valid signing profiles and the locally built tun2proxy
framework. Output is stored in an isolated directory, never in the git tree.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parents[1]
VERSION = '0.1.41'
BUILD = '46'  # verified against Apple API latest 0.1.40 build 45 on 2026-10-30
APP_NAME = 'Arvectum Proxy Launcher.app'
TEAM = 'VML75VY94V'


def run(*args, cwd=None, stdout=None):
    subprocess.run(list(map(str,args)),cwd=cwd,stdout=stdout,check=True)


def prepare(source, target, framework):
    if target.exists():
        raise RuntimeError('Staging path already exists: '+str(target))
    if not (framework/'Info.plist').is_file():
        raise RuntimeError('Missing signed VPN framework: '+str(framework))
    shutil.copytree(source,target,ignore=shutil.ignore_patterns('*.xcarchive','DerivedData'))
    spec=target/'project.yml'
    data=spec.read_text(encoding='utf-8')
    for old,new in [('MARKETING_VERSION: "0.1.39"','MARKETING_VERSION: "'+VERSION+'"'),
                    ('CURRENT_PROJECT_VERSION: "43"','CURRENT_PROJECT_VERSION: "'+BUILD+'"')]:
        if data.count(old)!=1:raise RuntimeError('Unexpected version template; refuse to change source: '+old)
        data=data.replace(old,new)
    spec.write_text(data,encoding='utf-8')
    dest=target/'Frameworks'/'tun2proxy.xcframework'
    dest.parent.mkdir(exist_ok=True,parents=True)
    dest.symlink_to(framework.resolve(),target_is_directory=True)
    return target


def export_options(path):
    values={'method':'app-store-connect','destination':'export','signingStyle':'manual',
            'teamID':TEAM,'provisioningProfiles':{
            'ru.arvectum.proxylauncher.ios':'APL App Store',
            'ru.arvectum.proxylauncher.ios.PacketTunnel':'APL Packet Tunnel App Store'}}
    with path.open('wb') as f:plistlib.dump(values,f)


def inspect(app, ipa, output):
    with (app/'Info.plist').open('rb') as f:info=plistlib.load(f)
    if info['CFBundleShortVersionString']!=VERSION or info['CFBundleVersion']!=BUILD:
        raise RuntimeError('Unexpected iOS app version or build number in signed archive')
    locales=list(app.glob('*.lproj/Localizable.strings'))
    extensions=list((app/'PlugIns').glob('*.appex'))
    if len(locales)!=50 or len(extensions)!=1:
        raise RuntimeError('Incomplete language/PacketTunnel archive')
    run('codesign','--verify','--deep','--strict',app)
    from zipfile import ZipFile
    with ZipFile(ipa) as z:
        files=z.namelist()
    strings=[name for name in files if name.startswith('Payload/') and name.endswith('.lproj/Localizable.strings')]
    tunnels=[name for name in files if name.endswith('.appex/Info.plist')]
    if len(strings)!=50 or len(tunnels)!=1:
        raise RuntimeError('Incomplete IPA payload')
    checksum=hashlib.sha256(ipa.read_bytes()).hexdigest()
    manifest={'version':VERSION,'build':BUILD,'status':'local_candidate_not_uploaded',
              'ipa':str(ipa),'sha256':checksum,'size':ipa.stat().st_size,
              'iosLocalizations':50,'packetTunnelExtensions':1,
              'appleSubmissionChanged':False}
    (output/'candidate-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('SIGNED_CANDIDATE_READY',json.dumps(manifest))
    return manifest


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True,type=Path,help='New (nonexistent) isolated output folder')
    parser.add_argument('--framework',type=Path,default=Path.home()/'proxy-launcher-ios-build39/mobile/ios/Frameworks/tun2proxy.xcframework')
    parser.add_argument('--prepare-only',action='store_true',help='Only stage source and generate project')
    args=parser.parse_args(argv)
    output=args.output.expanduser().resolve()
    source=SOURCE.resolve()
    if output==source or source in output.parents or output in source.parents:
        parser.error('Output cannot be the repository or a subdirectory/parent of it')
    if output.exists():
        parser.error('Output already exists; choose a new directory to preserve previous signed candidates')
    output.mkdir(parents=True)
    stage=prepare(source,output/'ios-source',args.framework)
    run('xcodegen','generate','--spec','project.yml',cwd=stage)
    if args.prepare_only:
        print('ISOLATED_SOURCE_READY',stage,VERSION,BUILD)
        return 0
    archive=output/'APL-0.1.41-46.xcarchive'
    export=output/'exported'
    options=output/'export-options.plist'
    export_options(options)
    with (output/'archive.log').open('w') as log:
        run('xcodebuild','-project','ArvectumProxyLauncherIOS.xcodeproj',
            '-scheme','ArvectumProxyLauncher','-configuration','Release',
            '-destination','generic/platform=iOS','-archivePath',archive,'archive',cwd=stage,stdout=log)
    with (output/'export.log').open('w') as log:
        run('xcodebuild','-exportArchive','-archivePath',archive,
            '-exportOptionsPlist',options,'-exportPath',export,cwd=stage,stdout=log)
    app=archive/'Products'/'Applications'/APP_NAME
    ipas=list(export.glob('*.ipa'))
    if len(ipas)!=1:raise RuntimeError('IPA export was not unique')
    inspect(app,ipas[0],output)
    return 0


if __name__=='__main__':
    try:sys.exit(main())
    except (RuntimeError,subprocess.CalledProcessError) as exc:
        print('CANDIDATE_BUILD_FAILED',str(exc),file=sys.stderr)
        sys.exit(1)
