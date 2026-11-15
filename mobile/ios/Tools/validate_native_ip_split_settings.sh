#!/bin/bash
# No network/preference/device operations. Allocate and inspect SDK objects only.
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-native-ip-split-settings.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
sources=("$root"/SharedCore/*.swift "$root/Shared/NativeTunnelNetworkSettings.swift" "$root/Tools/NativeIPSplitSettingsValidation.swift")
flags=(-D DEBUG -D APL_NATIVE_IP_ROUTE_REVIEW -D APL_NATIVE_PROVIDER_INTEGRATION -D APL_NATIVE_SYNTHETIC_RUNTIME -D APL_NATIVE_SYNTHETIC_SPLIT_ROUTE -D APL_NATIVE_AWG_CANDIDATE)
xcrun --sdk macosx swiftc -target arm64-apple-macos13.0 "${flags[@]}" -framework NetworkExtension "${sources[@]}" -o "$work/validate"
"$work/validate"
xcrun --sdk iphoneos swiftc -target arm64-apple-ios15.0 -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" "${flags[@]}" -typecheck "${sources[@]}"
echo NATIVE_EXPLICIT_IP_SETTINGS_IPHONEOS_TYPECHECK_PASS
