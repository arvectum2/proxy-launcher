#!/bin/bash
# Isolated QA-only iOS app; NO signing, installation or device/network change.
set -euo pipefail
umask 077
[[ $# == 2 || ( $# == 3 && "$3" == --product-unified ) ]] || { echo 'usage: build_unsigned.sh PINNED_IOS_SOURCE NEW_OUTPUT_DIR' >&2;exit 2; }
source="$1";out="$2";mode="${3:-standalone}"
[[ ! -e "$out" ]] || { echo OUTPUT_EXISTS >&2;exit 2; }
root="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ "$mode" == --product-unified ]];then
  python3 - "$source" <<'PIN'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1])
def sha(f):
    with f.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
assert sha(p/'manifest.json')=='1c8f00a729dac97e7670b718d6208d8e67946ea9b2260a9f68eed4a9fa5e0c54'
m=json.loads((p/'manifest.json').read_text())
assert not m['release_authorized'] and not m['runtime_authorized']
for n,h in m['files'].items():
    f=p/n
    assert f.resolve().is_relative_to(p.resolve()) and sha(f)==h
assert sha(p/'libAPLUnified.a')==m['archive_sha256']=='45716d42d434ae6d6576d9a32f47a4ea63d4943f106cb3bb7e6af57c725ea7af'
assert sha(p/'libAPLUnified.h')=='6307e010d9be17c82e7875acf0b86c962b8b8b32bd45994f523b39a51ba33505'
PIN
  lib=APLUnified;header=libAPLUnified.h;module=APLUnifiedGo
else
  python3 "$root/Tools/verify_xray_source_candidate.py" "$source" >/dev/null
  lib=Xray;header=libXray.h;module=LibXray
fi
mkdir -m 700 "$out"
mkdir -p "$out/Lib/Headers" "$out/Host" "$out/SharedCore"
cp "$source/lib$lib.a" "$out/Lib/"
cp "$source/$header" "$out/Lib/Headers/"
printf 'module %s [system] {\n  header "%s"\n  export *\n}\n' "$module" "$header" > "$out/Lib/Headers/module.modulemap"
cp "$root/Tools/DirectVLESSHardwareQA/Host/DirectVLESSQA.swift" "$out/Host/"
cp "$root/Tools/NativeTunnelLab/NativeLabRuntime.swift" "$out/Host/"
cp "$root"/SharedCore/*.swift "$out/SharedCore/"
cat > "$out/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>APL Direct Xray QA</string>
<key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
<key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
<key>CFBundleName</key><string>APLDirectXrayQA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>NSLocalNetworkUsageDescription</key><string>Contact a synthetic peer on the owner's private test network.</string>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
cat > "$out/project.yml" <<'YAML'
name: APLDirectXrayQA
options:
  deploymentTarget:
    iOS: '15.0'
targets:
  DirectXrayQA:
    type: application
    platform: iOS
    sources:
      - Host
      - SharedCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.proxylauncher.lab.directxray
        PRODUCT_NAME: APLDirectXrayQA
        INFOPLIST_FILE: Info.plist
        SWIFT_VERSION: '5.9'
        ENABLE_DEBUG_DYLIB: NO
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGNING_REQUIRED: NO
        SWIFT_INCLUDE_PATHS: '$(PROJECT_DIR)/Lib/Headers'
        LIBRARY_SEARCH_PATHS: '$(PROJECT_DIR)/Lib'
        OTHER_LDFLAGS: '-lXray -lresolv -framework SystemConfiguration -framework Security -framework CoreFoundation'
schemes:
  DirectXrayQA:
    build:
      targets:
        DirectXrayQA: all
YAML
if [[ "$mode" == --product-unified ]];then
  python3 - "$out/project.yml" <<'YAML_EDIT'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
assert s.count('-lXray ')==1
s=s.replace('-lXray ','-lAPLUnified ').replace("        SWIFT_VERSION: '5.9'","        SWIFT_VERSION: '5.9'\n        SWIFT_ACTIVE_COMPILATION_CONDITIONS: 'APL_DIRECT_PRODUCT_GO_QA'")
p.write_text(s)
YAML_EDIT
fi
(cd "$out" && xcodegen generate >/dev/null)
if ! xcodebuild -project "$out/APLDirectXrayQA.xcodeproj" -scheme DirectXrayQA -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO COMPILER_INDEX_STORE_ENABLE=NO -derivedDataPath "$out/Build" build > "$out/build.log" 2>&1; then
  grep -E 'error:|BUILD FAILED' "$out/build.log" | tail -30 || true
  exit 1
fi
app="$out/Build/Build/Products/Debug-iphoneos/APLDirectXrayQA.app"
test -f "$app/APLDirectXrayQA"
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist") == ru.arvectum.proxylauncher.lab.directxray ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist") == APLDirectXrayQA ]]
if find "$app" -name '*.appex' -o -name 'embedded.mobileprovision' | grep -q .;then echo INVALID_BUNDLE >&2;exit 1;fi
xcrun nm "$app/APLDirectXrayQA" > "$out/symbols.txt"
grep -qE ' [Tt] _CGoInvoke$' "$out/symbols.txt"
python3 - "$source" "$app/APLDirectXrayQA" "$out" "$lib" "$header" "$mode" <<'PY'
import hashlib,json,pathlib,sys
source,binary,out=map(pathlib.Path,sys.argv[1:4]);lib,header,mode=sys.argv[4:]
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
report={'engine_variant':mode,'qa_only':True,'signed':False,'device_modified':False,'network_extension':False,'source_library_sha256':sha(source/('lib'+lib+'.a')),'source_header_sha256':sha(source/header),'binary_sha256':sha(binary),'release_authorized':False}
(out/'manifest.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n')
print('IOS_DIRECT_XRAY_QA_UNSIGNED_BUILD_PASS',report['binary_sha256'])
PY
