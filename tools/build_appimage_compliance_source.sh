#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
source tools/appimage-toolchain.lock
cache="\${APPIMAGE_COMPLIANCE_CACHE:-$repo_root/.cache/appimage-compliance}"
out_dir="\${1:-dist/appimage}"
version="$(tr -d '[:space:]' < VERSION)"
runtime_archive="$cache/type2-runtime-\${APPIMAGE_RUNTIME_SOURCE_COMMIT}.tar.gz"
libfuse="$cache/libfuse-\${LIBFUSE_VERSION}.tar.xz"
squashfuse="$cache/squashfuse-\${SQUASHFUSE_VERSION}.tar.gz"

test -s "$runtime_archive"
test -s "$libfuse"
test -s "$squashfuse"
echo "$LIBFUSE_SOURCE_SHA256  $libfuse" | sha256sum -c -
echo "$SQUASHFUSE_SOURCE_SHA256  $squashfuse" | sha256sum -c -
tar -tzf "$runtime_archive" | grep -q "type2-runtime-\${APPIMAGE_RUNTIME_SOURCE_COMMIT}/src/runtime/Makefile$"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
bundle="$work/Arvectum-Proxy-Launcher-\${version}-linux-appimage-corresponding-source"
mkdir -p "$bundle" "$out_dir"
cp "$runtime_archive" "$bundle/"
cp "$libfuse" "$bundle/"
cp "$squashfuse" "$bundle/"
cp tools/appimage-toolchain.lock "$bundle/appimage-toolchain.lock"
cat > "$bundle/README.txt" <<EOF
Arvectum Proxy Launcher AppImage runtime corresponding-source companion

Product version: $version
Type-2 runtime source commit: $APPIMAGE_RUNTIME_SOURCE_COMMIT
Type-2 runtime distributed SHA-256: $APPIMAGE_RUNTIME_SHA256
libfuse source: $LIBFUSE_VERSION / $LIBFUSE_SOURCE_SHA256
squashfuse source: $SQUASHFUSE_VERSION / $SQUASHFUSE_SOURCE_SHA256

This package accompanies the Linux AppImage. It contains the exact type2-runtime
source commit plus the source archives and repository patch/build instructions
used for the statically linked libfuse/squashfuse path. The Arvectum application
source itself is the source tree at the matching product release tag.

This is an engineering distribution control, not a legal opinion.
EOF

outer="$out_dir/Arvectum-Proxy-Launcher-\${version}-linux-appimage-corresponding-source.tar.gz"
tar_file="$work/source.tar"
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
  -C "$work" -cf "$tar_file" "$(basename "$bundle")"
gzip -n -9 < "$tar_file" > "$outer"
test -s "$outer"
tar -tzf "$outer" | grep -q "type2-runtime-\${APPIMAGE_RUNTIME_SOURCE_COMMIT}.tar.gz"
tar -tzf "$outer" | grep -q "libfuse-\${LIBFUSE_VERSION}.tar.xz"
tar -tzf "$outer" | grep -q "squashfuse-\${SQUASHFUSE_VERSION}.tar.gz"
echo "$outer"
