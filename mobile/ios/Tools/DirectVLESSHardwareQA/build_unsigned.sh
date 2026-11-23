#!/bin/bash
# Isolated QA-only iOS app; NO signing, installation or device/network change.
set -euo pipefail
umask 077
[[ $# == 2 ]] || { echo 'usage: build_unsigned.sh PINNED_IOS_SOURCE NEW_OUTPUT_DIR' >&2;exit 2; }
source="$1";out="$2"
[[ ! -e "$out" ]] || { echo OUTPUT_EXISTS >&2;exit 2; }
root="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$root/Tools/verify_xray_source_candidate.py" "$source" >/dev/null
mkdir -m 700 "$out"
mkdir -p "$out/Lib/Headers" "$out/Host" "$out/SharedCore"
cp "$source/libXray.a" "$out/Lib/"
cp "$source/libXray.h" "$out/Lib/Headers/"
printf 'module LibXray [system] {\n  header "libXray.h"\n  export *\n}\n' > "$out/Lib/Headers/module.modulemap"
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
python3 - "$source" "$app/APLDirectXrayQA" "$out" <<'PY'
import hashlib,json,pathlib,sys
source,binary,out=map(pathlib.Path,sys.argv[1:])
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
report={'qa_only':True,'signed':False,'device_modified':False,'network_extension':False,'source_library_sha256':sha(source/'libXray.a'),'source_header_sha256':sha(source/'libXray.h'),'binary_sha256':sha(binary),'release_authorized':False}
(out/'manifest.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n')
print('IOS_DIRECT_XRAY_QA_UNSIGNED_BUILD_PASS',report['binary_sha256'])
PY
