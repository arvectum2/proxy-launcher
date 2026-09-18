#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
source tools/appimage-toolchain.lock
cache="\${APPIMAGE_COMPLIANCE_CACHE:-$repo_root/.cache/appimage-compliance}"
mkdir -p "$cache"

fetch_hash() {
  local url="$1" out="$2" sha="$3"
  if [[ ! -f "$out" ]] || ! echo "$sha  $out" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$out"
    curl --fail --location --retry 3 --silent --show-error "$url" --output "$out"
  fi
  echo "$sha  $out" | sha256sum -c -
}

runtime_repo="$cache/type2-runtime.git"
runtime_archive="$cache/type2-runtime-\${APPIMAGE_RUNTIME_SOURCE_COMMIT}.tar.gz"
if [[ ! -d "$runtime_repo/.git" ]]; then
  rm -rf "$runtime_repo"
  git init -q "$runtime_repo"
  git -C "$runtime_repo" remote add origin "$APPIMAGE_RUNTIME_REPOSITORY"
fi
git -C "$runtime_repo" fetch -q --depth=1 origin "$APPIMAGE_RUNTIME_SOURCE_COMMIT"
test "$(git -C "$runtime_repo" rev-parse FETCH_HEAD)" = "$APPIMAGE_RUNTIME_SOURCE_COMMIT"
git -C "$runtime_repo" archive --format=tar --prefix="type2-runtime-\${APPIMAGE_RUNTIME_SOURCE_COMMIT}/" FETCH_HEAD \
  | gzip -n > "$runtime_archive"
test -s "$runtime_archive"
tar -tzf "$runtime_archive" | grep -q "type2-runtime-\${APPIMAGE_RUNTIME_SOURCE_COMMIT}/src/runtime/Makefile$"

libfuse="$cache/libfuse-\${LIBFUSE_VERSION}.tar.xz"
squashfuse="$cache/squashfuse-\${SQUASHFUSE_VERSION}.tar.gz"
fetch_hash "$LIBFUSE_SOURCE_URL" "$libfuse" "$LIBFUSE_SOURCE_SHA256"
fetch_hash "$SQUASHFUSE_SOURCE_URL" "$squashfuse" "$SQUASHFUSE_SOURCE_SHA256"

printf '%s\n' "$runtime_archive" "$libfuse" "$squashfuse"
