#!/bin/bash
# Build a standalone pinned non-Xray host peer, not a production component.
set -euo pipefail
umask 077
[[ $# == 3 && "$(uname -m)" == arm64 ]]
source_dir="$(cd "$1" && pwd)"
archive="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
output="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
[[ "$(git -C "$source_dir" rev-parse HEAD)" == f333402bd9cbe0f3eeb02507bd14e23d7d639280 ]]
[[ -z "$(git -C "$source_dir" status --porcelain)" ]]
[[ "$(shasum -a256 "$source_dir/go.mod" | awk '{print $1}')" == 87e5574c17f1c8d3badd9195d933237c289c07b5813f4e60ceae36c7b270e288 ]]
[[ "$(shasum -a256 "$source_dir/go.sum" | awk '{print $1}')" == 1aa8ba6a11e01ea4554607a7dd5402132b6912e6d4704474986d3044cef1ff69 ]]
[[ "$(shasum -a256 "$archive" | awk '{print $1}')" == 544932844156d8172f7a28f77f2ac9c15a23046698b6243f633b0a0b00c0749c ]]
root="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-wg-reference.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
tar -xzf "$archive" -C "$work"
export PATH="$work/go/bin:$PATH" GOTOOLCHAIN=local GOWORK=off
mkdir "$work/lab"
ln -s "$source_dir" "$work/upstream"
cp "$root"/main.go "$root"/go.mod "$root"/go.sum "$work/lab/"
cd "$work/lab"
go mod verify
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -mod=readonly -trimpath -o "$output" .
go version -m "$output" >"$work/modules"
grep -F 'golang.zx2c4.com/wireguard' "$work/modules"
if grep -Ei '^[[:space:]]*(dep|mod)[[:space:]].*(xray|amnezia)' "$work/modules"; then exit 1; fi
shasum -a256 "$output"
echo APL_WG_REFERENCE_PINNED_PEER_BUILD_PASS
