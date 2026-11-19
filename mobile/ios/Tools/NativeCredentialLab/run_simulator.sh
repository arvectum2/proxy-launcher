#!/bin/bash
# Disposable simulator ONLY; never runs on the owner's device or Keychain.
set -euo pipefail
umask 077
[[ $# == 1 && "$1" == com.apple.CoreSimulator.SimRuntime.iOS-* ]]
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-credential-sim.XXXXXX")"
sim=""
cleanup(){ if [[ -n "$sim" ]]; then xcrun simctl shutdown "$sim" >/dev/null 2>&1 || true; xcrun simctl delete "$sim" >/dev/null 2>&1 || true; fi; rm -rf -- "$work"; }
trap cleanup EXIT
cat > "$work/AppShared.swift" <<'SWIFT'
enum AppShared {
    static let keychainAccessGroup: String? = "SIMQA00000.ru.arvectum.proxylauncher.credentialqa.shared"
    static let nativeCredentialServicePrefix = "ru.arvectum.proxylauncher.credentialqa."
}
SWIFT
mkdir "$work/Sources"
mv "$work/AppShared.swift" "$work/Sources/"
cp "$root/Shared/NativeCredentialKeychain.swift" "$root/Tools/NativeCredentialLab/SimCredentialLab.swift" "$work/Sources/"
cp "$root"/SharedCore/{NativeCredentialRecord,NativeCredentialHandoff,NativeCredentialCatalog,NativeProfileBackupCodec,ProfileBackup,NativeCredentialReceiver,VLESSRealityShareLink,XrayVLESSRuntimeConfig,NativeWireGuardRuntimeConfig,NativeTunnelRoutePlan,TransportNativeControl,TransportBackendContract,WGQuickConfigurationPreview,ManagedProfileContract,ProxyModel}.swift "$work/Sources/"
python3 - "$work" <<'PYPROJECT'
import pathlib,json,plistlib,sys
w=pathlib.Path(sys.argv[1]);targets={};schemes={}
for role in ('sender','receiver'):
    name='CredentialQA'+role.capitalize();ident='ru.arvectum.proxylauncher.credentialqa.'+role;team='SIMQA00000'
    (w/(role+'.entitlements')).write_bytes(plistlib.dumps({'application-identifier':team+'.'+ident,'com.apple.developer.team-identifier':team,'keychain-access-groups':[team+'.ru.arvectum.proxylauncher.credentialqa.shared']}))
    targets[name]={'type':'application','platform':'iOS','sources':['Sources'],'info':{'path':role+'-Info.plist','properties':{'UILaunchScreen':{}}},'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':ident,'SWIFT_VERSION':'5.0','ENABLE_DEBUG_DYLIB':'NO','TARGETED_DEVICE_FAMILY':'1','CODE_SIGNING_ALLOWED':'NO'}}}
    schemes[name]={'build':{'targets':{name:'all'}}}
(w/'project.json').write_text(json.dumps({'name':'CredentialQA','options':{'deploymentTarget':{'iOS':'15.0'}},'targets':targets,'schemes':schemes}))
PYPROJECT
(cd "$work" && xcodegen generate --spec project.json >/dev/null)
for role in sender receiver; do
  if [[ "$role" == sender ]]; then name=CredentialQASender; else name=CredentialQAReceiver; fi
  if ! xcodebuild -project "$work/CredentialQA.xcodeproj" -scheme "$name" -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -derivedDataPath "$work/Build" build >"$work/$role-build.log" 2>&1; then grep -E 'error:|BUILD FAILED' "$work/$role-build.log" | tail -12; exit 2; fi
  cp -R "$work/Build/Build/Products/Debug-iphonesimulator/$name.app" "$work/$role.app"
  codesign --force --sign - --entitlements "$work/$role.entitlements" "$work/$role.app"
  codesign --verify --strict "$work/$role.app"
  echo "SIMULATOR_APP_BUILD_$role"
done
sim="$(xcrun simctl create "APL-CredentialQA-$$" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$1")"
xcrun simctl boot "$sim"
python3 - "$sim" <<'PY'
import json,subprocess,sys
s=sys.argv[1]
subprocess.run(['xcrun','simctl','bootstatus',s,'-b'],check=True,timeout=120,stdout=subprocess.DEVNULL)
print('SIMULATOR_FULL_BOOT_READY',flush=True)
PY
for role in sender receiver; do xcrun simctl install "$sim" "$work/$role.app"; done
base=ru.arvectum.proxylauncher.credentialqa
if ! xcrun simctl launch "$sim" "$base.sender" --synthetic-credential-lab; then echo SIMULATOR_APP_LAUNCH_FAILED; exit 4; fi
src="$(xcrun simctl get_app_container "$sim" "$base.sender" data)/Documents"
for i in {1..40}; do [[ ! -s "$src/exchange.json" && ! -s "$src/result.json" ]] || break; sleep .5; done
[[ -s "$src/exchange.json" ]] || { echo SENDER_NO_EXCHANGE; exit 3; }
xcrun simctl terminate "$sim" "$base.sender"
dst="$(xcrun simctl get_app_container "$sim" "$base.receiver" data)/Documents"; mkdir -p "$dst"; cp "$src/exchange.json" "$dst/exchange.json"
xcrun simctl launch "$sim" "$base.receiver" --synthetic-credential-lab
for i in {1..40}; do [[ ! -s "$dst/result.json" ]] || break; sleep .5; done
python3 - "$dst/result.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]));print({k:r[k] for k in ('pass','distinctProcess','replayRejected','cleaned')});assert all(r[k] is True for k in ('pass','distinctProcess','replayRejected','cleaned'))
PY
echo SIMULATOR_CROSS_PROCESS_CREDENTIAL_PASS
