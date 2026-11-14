#!/bin/bash
# Local-only prototype. Does not link Xray, create system TUN or sign/install apps.
set -euo pipefail
umask 077
[[ $# == 3 ]] || { echo "usage: $0 PINNED_AWG_CHECKOUT PINNED_GO_TAR IOS_SIM_RUNTIME"; exit 2; }
source_dir="$(cd "$1" && pwd)"
archive="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
runtime="$3"
[[ "$runtime" == com.apple.CoreSimulator.SimRuntime.iOS-* && "$(uname -m)" == arm64 ]]
[[ "$(git -C "$source_dir" rev-parse HEAD)" == b5928efb6ca19f0153958460c3d141f04abc5c2e ]]
[[ -z "$(git -C "$source_dir" status --porcelain)" ]]
[[ "$(shasum -a256 "$source_dir/go.mod" | awk '{print $1}')" == 9fd0084da2acc4f96225daee85c0f866a0ec1079d5bdc4cf98c50e8a8fa0baf6 ]]
[[ "$(shasum -a256 "$source_dir/go.sum" | awk '{print $1}')" == eab202288b6f879fe1f6b0d9da0c528cfb310d74a7a4d409c7268c2b26b98a0a ]]
[[ "$(shasum -a256 "$archive" | awk '{print $1}')" == 544932844156d8172f7a28f77f2ac9c15a23046698b6243f633b0a0b00c0749c ]]
root="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-awg-native.XXXXXX")"
sim=""
cleanup(){
    if [[ -n "$sim" ]]; then
        xcrun simctl shutdown "$sim" >/dev/null 2>&1 || true
        xcrun simctl delete "$sim" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT
tar -xzf "$archive" -C "$work"
export PATH="$work/go/bin:$PATH" GOTOOLCHAIN=local GOWORK=off
go version
mkdir "$work/lab"
ln -s "$source_dir" "$work/awg"
cp "$root"/main.go "$root"/go.mod "$root"/go.sum "$work/lab/"
cp "$root/launcher.c.txt" "$work/launcher.c"
cd "$work/lab"
go mod verify
for platform in macosx iphonesimulator iphoneos; do
    sdk="$(xcrun --sdk "$platform" --show-sdk-path)"
    case "$platform" in
      macosx) target=arm64-apple-macos13.0; os=darwin ;;
      iphonesimulator) target=arm64-apple-ios15.0-simulator; os=ios ;;
      iphoneos) target=arm64-apple-ios15.0; os=ios ;;
    esac
    cc="$(xcrun --sdk "$platform" --find clang)"
    flags="-target $target -isysroot $sdk"
    CGO_ENABLED=1 GOOS="$os" GOARCH=arm64 CC="$cc" CGO_CFLAGS="$flags" CGO_LDFLAGS="$flags" \
        go build -mod=readonly -trimpath -buildmode=c-archive -o "$work/lib-$platform.a" .
    "$cc" -target "$target" -isysroot "$sdk" "$work/launcher.c" "$work/lib-$platform.a" \
        -framework Security -framework CoreFoundation -lresolv -o "$work/qa-$platform"
    xcrun nm "$work/qa-$platform" >"$work/symbols"
    grep -E ' [Tt] _aplAWGSelfTest$' "$work/symbols"
    if grep -qE ' [Tt] _CGoInvoke$' "$work/symbols"; then echo "Unexpected Xray symbol"; exit 1; fi
    shasum -a256 "$work/lib-$platform.a" | awk '{print $1}'
    echo "APL_AWG_LINK_$platform"
done
"$work/qa-macosx"
echo APL_AWG_MAC_NATIVE_PASS
codesign --force --sign - "$work/qa-iphonesimulator"
sim="$(xcrun simctl create "APL-AWGNativeQA-$$" com.apple.CoreSimulator.SimDeviceType.iPhone-13 "$runtime")"
xcrun simctl boot "$sim"
xcrun simctl bootstatus "$sim" -b >/dev/null
xcrun simctl spawn "$sim" "$work/qa-iphonesimulator"
echo APL_AWG_SIM_NATIVE_PASS
