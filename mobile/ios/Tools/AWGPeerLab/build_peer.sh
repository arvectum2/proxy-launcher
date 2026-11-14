#!/bin/bash
# Verified upstream source and toolchain; no network, persistent service or signing.
set -euo pipefail
umask 077
[[ $# == 3 && "$(uname -m)" == arm64 ]]
source_dir="$(cd "$1" && pwd)"
archive="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
output="$(cd "$3" && pwd)"
[[ "$(git -C "$source_dir" rev-parse HEAD)" == b5928efb6ca19f0153958460c3d141f04abc5c2e && -z "$(git -C "$source_dir" status --porcelain)" ]]
[[ "$(shasum -a256 "$source_dir/go.mod" | awk '{print $1}')" == 9fd0084da2acc4f96225daee85c0f866a0ec1079d5bdc4cf98c50e8a8fa0baf6 ]]
[[ "$(shasum -a256 "$source_dir/go.sum" | awk '{print $1}')" == eab202288b6f879fe1f6b0d9da0c528cfb310d74a7a4d409c7268c2b26b98a0a ]]
[[ "$(shasum -a256 "$archive" | awk '{print $1}')" == 544932844156d8172f7a28f77f2ac9c15a23046698b6243f633b0a0b00c0749c ]]
root="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-awg-peer-build.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/peer" "$work/bridge"
ln -s "$source_dir" "$work/awg"
cp "$root"/main.go "$root"/go.mod "$root"/go.sum "$root/../AWGNativeLab/scoped_bind.go" "$work/peer/"
cp "$root"/../AWGNativeLab/*.go "$root"/../AWGNativeLab/go.mod "$root"/../AWGNativeLab/go.sum "$work/bridge/"
tar -xzf "$archive" -C "$work"
export PATH="$work/go/bin:$PATH" GOTOOLCHAIN=local GOWORK=off GOPROXY=off
(cd "$work/peer" && go mod verify && go build -mod=readonly -trimpath -o "$work/awg-peer" .)
(cd "$work/bridge" && go mod verify && go test -mod=readonly ./... && go build -mod=readonly -trimpath -o "$work/awg-bridge" .)
python3 -u "$root/run_preflight.py" --peer "$work/awg-peer" --bridge "$work/awg-bridge"
# Publish test artifacts only after the independent receipt gate passes.
cp "$work/awg-peer" "$work/awg-bridge" "$output/"
(cd "$output" && shasum -a 256 awg-peer awg-bridge > SHA256SUMS)
echo AWG_PEER_BUILD_AND_PREFLIGHT_PASS
