#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/patches/tun2proxy-v0.8.3-http-udp-session-counter.patch"
TAG="v0.8.3"
COMMIT="e271de19683937f23d3f8f0eb4df0a61fc4a6e50"
NDK_VERSION="26.3.11579264"
ANDROID_API=21

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone --quiet --depth 1 --branch "$TAG" https://github.com/tun2proxy/tun2proxy.git "$work/tun2proxy"
cd "$work/tun2proxy"
actual="$(git rev-parse HEAD)"
test "$actual" = "$COMMIT" || {
  echo "Unexpected tun2proxy commit: $actual" >&2
  exit 1
}
git apply "$PATCH"

sdkmanager_bin="$(command -v sdkmanager || true)"
if [[ -z "$sdkmanager_bin" ]]; then
  sdkmanager_bin="$(find "$ANDROID_HOME/cmdline-tools" -type f -name sdkmanager | head -n 1)"
fi
test -x "$sdkmanager_bin"
"$sdkmanager_bin" --sdk_root="$ANDROID_HOME" "ndk;$NDK_VERSION" >/dev/null

rustup target add aarch64-linux-android
toolchain="$ANDROID_HOME/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/linux-x86_64/bin"
export CC_aarch64_linux_android="$toolchain/aarch64-linux-android${ANDROID_API}-clang"
export AR_aarch64_linux_android="$toolchain/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$toolchain/aarch64-linux-android${ANDROID_API}-clang"
export RUSTFLAGS="-C link-arg=-Wl,-z,common-page-size=16384 -C link-arg=-Wl,-z,max-page-size=16384 --cfg ANDROID_PAGE_SIZE_16K"
export CFLAGS="-D__PAGE_SIZE=16384 -DANDROID_PAGE_SIZE=16384"
export CPPFLAGS="-D__PAGE_SIZE=16384 -DANDROID_PAGE_SIZE=16384"

cargo build --release --target aarch64-linux-android

target="$ROOT/app/src/main/jniLibs/arm64-v8a/libtun2proxy.so"
mkdir -p "$(dirname "$target")"
cp "target/aarch64-linux-android/release/libtun2proxy.so" "$target"

marker="$ROOT/app/src/main/jniLibs/.tun2proxy-arm64-patch"
{
  echo "$TAG"
  echo "commit=$COMMIT"
  echo "patch=$(sha256sum "$PATCH" | awk '{print $1}')"
  echo "binary=$(sha256sum "$target" | awk '{print $1}')"
} > "$marker"

echo "Installed patched arm64 tun2proxy: $target"
