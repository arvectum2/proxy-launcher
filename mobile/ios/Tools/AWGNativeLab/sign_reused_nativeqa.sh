#!/bin/bash
# Explicitly approved reuse of previously issued NativeLab profiles only.
# No Apple Developer portal access, certificate creation, or provisioning updates.
set -euo pipefail
umask 077
[[ $# == 4 && "$1" == --approved-reuse ]]
root="$(cd "$(dirname "$0")" && pwd)"
base="$(cd "$2" && pwd)"
source="$(cd "$3" && pwd)"
dest="$(cd "$4" && pwd)"
app_name="$(basename "$source")"
case "$app_name" in
    AWGCompileHost.app) extension=AWGProvider.appex; sums=AWG-SHA256SUMS; verifier="$root/verify_signed_awg.py" ;;
    NativeLabHost.app) extension=NativeLab.appex; sums=NATIVE-SHA256SUMS; verifier="$root/../NativeTunnelLab/verify_signed_lab.py" ;;
    *) echo 'Not an existing NativeLab variant' >&2; exit 2 ;;
esac
[[ ! -e "$dest/$app_name" ]]
# Debug dylibs are not expected; reject rather than signing an incomplete bundle.
[[ -z "$(find "$source" -name '*.dylib' -print)" ]]
python3 "$root/../NativeTunnelLab/verify_signed_lab.py" "$base"
codesign --verify --deep --strict "$base"
(cd "$(dirname "$source")" && shasum -a 256 -c "$sums")
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-awg-sign-reuse.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp -R "$source" "$work/$app_name"
python3 - "$base" "$work" "$app_name" "$extension" <<'PY'
import datetime, hashlib, pathlib, plistlib, shutil, subprocess, sys
base, work = map(pathlib.Path, sys.argv[1:3])
app = work/sys.argv[3]
extension = sys.argv[4]
identity = None
for name, old, new, suffix in [('host',base,app,''),('provider',base/'PlugIns/NativeLab.appex',app/'PlugIns'/extension,'.PacketTunnel')]:
    ident = 'ru.arvectum.proxylauncher.lab.nativeqa'+suffix
    assert plistlib.loads((new/'Info.plist').read_bytes())['CFBundleIdentifier']==ident
    assert not (new/'embedded.mobileprovision').exists()
    profile = plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(old/'embedded.mobileprovision')],stderr=subprocess.DEVNULL))
    assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    assert len(profile['DeveloperCertificates'])==1
    cert=hashlib.sha1(profile['DeveloperCertificates'][0]).hexdigest().upper()
    assert identity is None or identity==cert
    identity=cert
    actual=subprocess.check_output(['codesign','-d','--entitlements',':-',str(old)],stderr=subprocess.DEVNULL)
    (work/(name+'.plist')).write_bytes(actual)
    shutil.copyfile(old/'embedded.mobileprovision',new/'embedded.mobileprovision')
assert identity in subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
(work/'identity').write_text(identity)
PY
app="$work/$app_name"
identity="$(cat "$work/identity")"
codesign --force --sign "$identity" --entitlements "$work/provider.plist" --timestamp=none "$app/PlugIns/$extension"
codesign --force --sign "$identity" --entitlements "$work/host.plist" --timestamp=none "$app"
codesign --verify --deep --strict "$app"
python3 "$verifier" "$app"
cp -R "$app" "$dest/"
codesign --verify --deep --strict "$dest/$app_name"
echo "REUSED_NATIVEQA_OFFLINE_SIGN_PASS $app_name"
