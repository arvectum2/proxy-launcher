#!/bin/bash
# Actual product sources, separate unsigned AWG compile lane. No install/run.
set -euo pipefail
umask 077
[[ $# == 4 ]] || { echo 'usage: build_product_awg_candidate_unsigned.sh AWG_SOURCE GO_TAR RUST_FRAMEWORK NEW_OUTPUT_DIR' >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
source="$(cd "$1" && pwd)"; go_tar="$2"; rust="$3"; out="$4"
[[ ! -e "$out" && "$(uname -m)" == arm64 ]]
[[ "$(git -C "$source" rev-parse HEAD)" == b5928efb6ca19f0153958460c3d141f04abc5c2e && -z "$(git -C "$source" status --porcelain)" ]]
[[ "$(shasum -a 256 "$source/go.mod" | cut -d' ' -f1)" == 9fd0084da2acc4f96225daee85c0f866a0ec1079d5bdc4cf98c50e8a8fa0baf6 ]]
[[ "$(shasum -a 256 "$source/go.sum" | cut -d' ' -f1)" == eab202288b6f879fe1f6b0d9da0c528cfb310d74a7a4d409c7268c2b26b98a0a ]]
[[ "$(shasum -a 256 "$go_tar" | cut -d' ' -f1)" == 544932844156d8172f7a28f77f2ac9c15a23046698b6243f633b0a0b00c0749c ]]
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-product-awg.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/lab" "$work/Lib/AWG" "$work/Lib/Rust/Headers"
ln -s "$source" "$work/awg"
cp "$root/Tools/AWGNativeLab/"*.go "$root/Tools/AWGNativeLab/go.mod" "$root/Tools/AWGNativeLab/go.sum" "$work/lab/"
tar -xzf "$go_tar" -C "$work"
export PATH="$work/go/bin:$PATH" GOTOOLCHAIN=local GOWORK=off GOPROXY=off
sdkpath="$(xcrun --sdk iphoneos --show-sdk-path)"; cc="$(xcrun --sdk iphoneos --find clang)"; flags="-target arm64-apple-ios15.0 -isysroot $sdkpath"
(cd "$work/lab" && go mod verify && go test -race -run '^TestProductUAPIValidationWithoutSockets$' -count=1 . && CGO_ENABLED=1 GOOS=ios GOARCH=arm64 CC="$cc" CGO_CFLAGS="$flags" CGO_LDFLAGS="$flags" go build -mod=readonly -trimpath -buildmode=c-archive -o "$work/Lib/AWG/libAWG.a" .)
printf 'module APLAWGBridge { header "libAWG.h" export * }\n' > "$work/Lib/AWG/module.modulemap"
python3 "$root/Tools/verify_tun2proxy_lab_artifact.py" "$rust" ios-arm64 --require-connected-udp
cp "$rust/ios-arm64/libtun2proxy.a" "$work/Lib/Rust/"
cp "$rust/ios-arm64/Headers/"* "$work/Lib/Rust/Headers/"
[[ $(shasum -a 256 "$work/Lib/Rust/libtun2proxy.a" | cut -d' ' -f1) == e81642cf494e218aeb3314289f235eeff8dff21dc8d72b8bd23ded8b41c0b852 ]]
cp -R "$root/PacketTunnel" "$root/Shared" "$root/SharedCore" "$work/"
cp "$root/Config/PacketTunnel-Info.plist" "$work/Info.plist"
cat > "$work/project.yml" <<'YAML'
name: APLProductAWGCompileOnly
options:
  deploymentTarget:
    iOS: '15.0'
targets:
  PacketTunnelCandidate:
    type: app-extension
    platform: iOS
    sources: [PacketTunnel, Shared, SharedCore]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.proxylauncher.lab.productawgcompile.PacketTunnel
        PRODUCT_NAME: PacketTunnelCandidate
        INFOPLIST_FILE: Info.plist
        MARKETING_VERSION: '0.2.0'
        CURRENT_PROJECT_VERSION: '48'
        SWIFT_VERSION: '5.9'
        APPLICATION_EXTENSION_API_ONLY: YES
        ENABLE_DEBUG_DYLIB: NO
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGNING_REQUIRED: NO
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: 'DEBUG APL_NATIVE_PROVIDER_INTEGRATION APL_NATIVE_AWG_CANDIDATE'
        SWIFT_INCLUDE_PATHS: '$(PROJECT_DIR)/Lib/AWG $(PROJECT_DIR)/Lib/Rust/Headers'
        LIBRARY_SEARCH_PATHS: '$(PROJECT_DIR)/Lib/AWG $(PROJECT_DIR)/Lib/Rust'
        OTHER_LDFLAGS: '-lAWG -ltun2proxy -lresolv -framework Security -framework CoreFoundation -framework NetworkExtension -framework SystemConfiguration'
schemes:
  PacketTunnelCandidate:
    build:
      targets:
        PacketTunnelCandidate: all
YAML
(cd "$work" && xcodegen generate >/dev/null)
if ! xcodebuild -project "$work/APLProductAWGCompileOnly.xcodeproj" -scheme PacketTunnelCandidate -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO COMPILER_INDEX_STORE_ENABLE=NO -derivedDataPath "$work/Build" build > "$work/build.log" 2>&1; then grep -E 'error:|BUILD FAILED' "$work/build.log" | tail -25; exit 1; fi
app="$work/Build/Build/Products/Debug-iphoneos/PacketTunnelCandidate.appex"
test -f "$app/PacketTunnelCandidate"
[[ -z "$(find "$app" -name embedded.mobileprovision -o -name '*.dylib')" ]]
xcrun nm "$app/PacketTunnelCandidate" > "$work/symbols.txt"
grep -E ' [Tt] _aplAWGBridgeValidateConfig$' "$work/symbols.txt"
grep -q 'NativeAWGValidationDriver' "$work/symbols.txt"
if grep -qE ' [Tt] _CGoInvoke$' "$work/symbols.txt"; then exit 1; fi
mkdir -m 700 "$out"
cp "$work/build.log" "$work/symbols.txt" "$out/"
python3 - "$root" "$work" "$app/PacketTunnelCandidate" "$out" <<'PY'
import hashlib,json,pathlib,sys,subprocess
root,work,binary,out=map(pathlib.Path,sys.argv[1:])
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
sources={}
for folder in ('PacketTunnel','Shared','SharedCore','lab'):
    for f in sorted((work/folder).rglob('*')):
        if not f.is_file():continue
        rel=str(f.relative_to(work));src=root/rel if folder!='lab' else root/'Tools/AWGNativeLab'/f.name
        sources[rel]=sha(f);assert sources[rel]==sha(src)
report={'schema':1,'release_authorized':False,'scope':'actual product AWG provider sources; unsigned compile/link only; no runtime authorization','base_commit':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),'awg_commit':'b5928efb6ca19f0153958460c3d141f04abc5c2e','sources':sources,'binary_sha256':sha(binary),'inputs':{str(p.relative_to(work)):sha(p) for p in sorted((work/'Lib').rglob('*')) if p.is_file()},'build_log_sha256':sha(out/'build.log'),'symbol_table_sha256':sha(out/'symbols.txt')}
(out/'manifest.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print('AWG_COMPILE_LINK_ONLY_PASS',report['binary_sha256'],len(sources),'sources')
PY
