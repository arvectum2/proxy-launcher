#!/bin/zsh
set -euo pipefail

CONFIG="${ARVECTUM_ASC_CONFIG:-${APL_ASC_CONFIG:-$HOME/.config/arvectum/appstore-connect.env}}"
[[ -r "$CONFIG" ]] || { echo "Missing App Store Connect config: $CONFIG" >&2; exit 2; }
source "$CONFIG"
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"

KEY_DIR="${ASC_KEY_DIR:-$HOME/.appstoreconnect/private_keys}"
KEY_FILE="$KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
[[ -r "$KEY_FILE" ]] || { echo "Missing private key" >&2; exit 2; }

XCODE="${ASC_XCODE:-/Applications/Xcode-26.6.0.app}"
ALTOOL="$XCODE/Contents/SharedFrameworks/ContentDelivery.framework/Versions/A/Resources/altool"
[[ -x "$ALTOOL" ]] || { echo "altool unavailable" >&2; exit 2; }
export API_PRIVATE_KEYS_DIR="$KEY_DIR"

make_token() {
  local jwt_file token
  jwt_file=$(mktemp)
  chmod 600 "$jwt_file"
  "$ALTOOL" --generate-jwt --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" >/dev/null 2>"$jwt_file"
  token=$(python3 - "$jwt_file" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', text)
if not match:
    raise SystemExit("JWT generation failed")
print(match.group(0), end="")
PY
)
  rm -f "$jwt_file"
  print -r -- "$token"
}

api_get() {
  local endpoint="$1" token body code
  token=$(make_token)
  body=$(mktemp)
  chmod 600 "$body"
  code=$(curl -sS -o "$body" -w '%{http_code}' -H "Authorization: Bearer $token" "https://api.appstoreconnect.apple.com$endpoint")
  if [[ "$code" != 2* ]]; then
    echo "App Store Connect API GET failed: HTTP $code" >&2
    python3 - "$body" <<'PY'
import json, sys
try:
    payload=json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit(1)
for error in payload.get("errors", []):
    print(error.get("status"), error.get("code"), error.get("title"), error.get("detail"), file=sys.stderr)
PY
    rm -f "$body"
    return 1
  fi
  cat "$body"
  rm -f "$body"
}

api_request() {
  local method="$1" endpoint="$2" payload="${3:-}" token body code
  token=$(make_token)
  body=$(mktemp)
  chmod 600 "$body"
  if [[ -n "$payload" ]]; then
    code=$(curl -sS -o "$body" -w '%{http_code}' -X "$method" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d "$payload" "https://api.appstoreconnect.apple.com$endpoint")
  else
    code=$(curl -sS -o "$body" -w '%{http_code}' -X "$method" -H "Authorization: Bearer $token" "https://api.appstoreconnect.apple.com$endpoint")
  fi
  if [[ "$code" != 2* ]]; then
    echo "App Store Connect API $method failed: HTTP $code" >&2
    python3 - "$body" <<'PY'
import json, sys
try: payload=json.load(open(sys.argv[1]))
except Exception: raise SystemExit(1)
for error in payload.get("errors", []):
    print(error.get("status"), error.get("code"), error.get("title"), error.get("detail"), file=sys.stderr)
PY
    rm -f "$body"
    return 1
  fi
  cat "$body"
  rm -f "$body"
}

find_bundle_id() {
  local identifier="$1" tmp
  tmp=$(mktemp); chmod 600 "$tmp"
  api_get '/v1/bundleIds?limit=200' >"$tmp"
  python3 - "$tmp" "$identifier" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1])); wanted=sys.argv[2]
for item in payload.get("data", []):
    if item.get("attributes", {}).get("identifier") == wanted:
        print(item.get("id")); break
PY
  rm -f "$tmp"
}

ensure_bundle_id() {
  local identifier="$1" name="$2" id payload tmp
  id=$(find_bundle_id "$identifier")
  if [[ -n "$id" ]]; then print -r -- "$id"; return 0; fi
  payload=$(python3 - "$identifier" "$name" <<'PY'
import json, sys
print(json.dumps({"data":{"type":"bundleIds","attributes":{"identifier":sys.argv[1],"name":sys.argv[2],"platform":"UNIVERSAL"}}}, separators=(",",":")))
PY
  )
  tmp=$(mktemp); chmod 600 "$tmp"
  api_request POST /v1/bundleIds "$payload" >"$tmp"
  python3 - "$tmp" <<'PY'
import json, sys; print(json.load(open(sys.argv[1]))["data"]["id"])
PY
  rm -f "$tmp"
}

ensure_capability() {
  local bundle_id="$1" capability="$2" tmp payload
  tmp=$(mktemp); chmod 600 "$tmp"
  api_get "/v1/bundleIds/$bundle_id/bundleIdCapabilities" >"$tmp"
  if python3 - "$tmp" "$capability" <<'PY'
import json, sys
p=json.load(open(sys.argv[1])); wanted=sys.argv[2]
raise SystemExit(0 if any(x.get("attributes",{}).get("capabilityType")==wanted for x in p.get("data",[])) else 1)
PY
  then rm -f "$tmp"; return 0; fi
  payload=$(python3 - "$bundle_id" "$capability" <<'PY'
import json, sys
print(json.dumps({"data":{"type":"bundleIdCapabilities","attributes":{"capabilityType":sys.argv[2]},"relationships":{"bundleId":{"data":{"type":"bundleIds","id":sys.argv[1]}}}}}, separators=(",",":")))
PY
  )
  api_request POST /v1/bundleIdCapabilities "$payload" >/dev/null
  rm -f "$tmp"
}

local_mac_udid() {
  system_profiler SPHardwareDataType | awk -F': ' '/Provisioning UDID/{print $2; exit}'
}

ensure_local_mac_device() {
  local udid tmp id payload name
  udid=$(local_mac_udid)
  [[ -n "$udid" ]] || { echo "Provisioning UDID unavailable" >&2; return 1; }
  tmp=$(mktemp); chmod 600 "$tmp"
  api_get '/v1/devices?limit=200' >"$tmp"
  id=$(python3 - "$tmp" "$udid" <<'PY'
import json, sys
p=json.load(open(sys.argv[1])); wanted=sys.argv[2]
for x in p.get("data",[]):
    if x.get("attributes",{}).get("udid")==wanted and x.get("attributes",{}).get("status")=="ENABLED":
        print(x.get("id")); break
PY
  )
  if [[ -n "$id" ]]; then rm -f "$tmp"; print -r -- "$id"; return 0; fi
  name=$(scutil --get ComputerName 2>/dev/null || hostname)
  payload=$(python3 - "$name" "$udid" <<'PY'
import json, sys
print(json.dumps({"data":{"type":"devices","attributes":{"name":sys.argv[1],"platform":"MAC_OS","udid":sys.argv[2]}}}, separators=(",",":")))
PY
  )
  api_request POST /v1/devices "$payload" >"$tmp"
  python3 - "$tmp" <<'PY'
import json, sys; print(json.load(open(sys.argv[1]))["data"]["id"])
PY
  rm -f "$tmp"
}

certificate_id() {
  local certificate_type="$1" tmp
  tmp=$(mktemp); chmod 600 "$tmp"; api_get '/v1/certificates?limit=200' >"$tmp"
  python3 - "$tmp" "$certificate_type" <<'PY'
import json, sys, datetime
p=json.load(open(sys.argv[1])); wanted=sys.argv[2]
for x in p.get("data",[]):
    a=x.get("attributes",{})
    if a.get("certificateType")==wanted and a.get("activated",True):
        print(x.get("id")); break
PY
  rm -f "$tmp"
}

ensure_profile() {
  local name="$1" profile_type="$2" bundle_id="$3" certificate_id="$4" device_id="${5:-}" tmp existing payload
  tmp=$(mktemp); chmod 600 "$tmp"; api_get '/v1/profiles?limit=200' >"$tmp"
  existing=$(python3 - "$tmp" "$name" "$profile_type" <<'PY'
import json, sys
p=json.load(open(sys.argv[1])); name=sys.argv[2]; typ=sys.argv[3]
for x in p.get("data",[]):
    a=x.get("attributes",{})
    if a.get("name")==name and a.get("profileType")==typ and a.get("profileState")=="ACTIVE":
        print(x.get("id")); break
PY
  )
  if [[ -n "$existing" ]]; then
    api_get "/v1/profiles/$existing" >"$tmp"
  else
    payload=$(python3 - "$name" "$profile_type" "$bundle_id" "$certificate_id" "$device_id" <<'PY'
import json, sys
name, typ, bundle, cert, device = sys.argv[1:]
rels={"bundleId":{"data":{"type":"bundleIds","id":bundle}},"certificates":{"data":[{"type":"certificates","id":cert}]}}
if device: rels["devices"]={"data":[{"type":"devices","id":device}]}
print(json.dumps({"data":{"type":"profiles","attributes":{"name":name,"profileType":typ},"relationships":rels}}, separators=(",",":")))
PY
    )
    api_request POST /v1/profiles "$payload" >"$tmp"
  fi
  python3 - "$tmp" <<'PY'
import base64, json, os, pathlib, sys
p=json.load(open(sys.argv[1])); a=p["data"]["attributes"]
root=pathlib.Path.home()/"Library/Developer/Xcode/UserData/Provisioning Profiles"; root.mkdir(parents=True,exist_ok=True)
path=root/(a["uuid"]+".mobileprovision"); path.write_bytes(base64.b64decode(a["profileContent"])); os.chmod(path,0o600)
print(p["data"]["id"], a["uuid"], path)
PY
  rm -f "$tmp"
}

bootstrap() {
  local app_id ext_id device_id development_id distribution_id
  app_id=$(ensure_bundle_id "ru.arvectum.proxylauncher.macos" "Arvectum Proxy Launcher macOS")
  ext_id=$(ensure_bundle_id "ru.arvectum.proxylauncher.macos.PacketTunnel" "Arvectum Proxy Launcher macOS Packet Tunnel")
  for id in "$app_id" "$ext_id"; do ensure_capability "$id" APP_GROUPS; ensure_capability "$id" NETWORK_EXTENSIONS; done
  device_id=$(ensure_local_mac_device)
  development_id=$(certificate_id DEVELOPMENT)
  distribution_id=$(certificate_id DISTRIBUTION)
  [[ -n "$development_id" && -n "$distribution_id" ]] || { echo "Required signing certificates unavailable" >&2; return 1; }
  echo "BOOTSTRAP bundle_app=$app_id bundle_tunnel=$ext_id device=$device_id"
  ensure_profile "APL Mac Development" MAC_CATALYST_APP_DEVELOPMENT "$app_id" "$development_id" "$device_id"
  ensure_profile "APL Mac Packet Tunnel Development" MAC_CATALYST_APP_DEVELOPMENT "$ext_id" "$development_id" "$device_id"
  ensure_profile "APL Mac App Store" MAC_CATALYST_APP_STORE "$app_id" "$distribution_id"
  ensure_profile "APL Mac Packet Tunnel App Store" MAC_CATALYST_APP_STORE "$ext_id" "$distribution_id"
}

doctor() {
  local tmp
  tmp=$(mktemp)
  chmod 600 "$tmp"
  api_get '/v1/bundleIds?limit=200' >"$tmp"
  python3 - "$tmp" <<'PY'
import json, sys
wanted={"ru.arvectum.proxylauncher.macos","ru.arvectum.proxylauncher.macos.PacketTunnel","ru.arvectum.proxylauncher.ios","ru.arvectum.proxylauncher.ios.PacketTunnel"}
payload=json.load(open(sys.argv[1]))
for item in payload.get("data", []):
    attrs=item.get("attributes", {})
    if attrs.get("identifier") in wanted:
        print("BUNDLE", item.get("id"), attrs.get("identifier"), attrs.get("platform"))
        if attrs.get("identifier") in {"ru.arvectum.proxylauncher.ios","ru.arvectum.proxylauncher.ios.PacketTunnel"}:
            print("CAPABILITY_URL", item.get("id"))
PY
  for bundle_id in $(python3 - "$tmp" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1]))
wanted={"ru.arvectum.proxylauncher.ios","ru.arvectum.proxylauncher.ios.PacketTunnel"}
for item in payload.get("data", []):
    if item.get("attributes", {}).get("identifier") in wanted:
        print(item.get("id"))
PY
  ); do
    api_get "/v1/bundleIds/$bundle_id/bundleIdCapabilities" >"$tmp"
    python3 - "$tmp" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1]))
for item in payload.get("data", []):
    a=item.get("attributes", {})
    print("CAP", a.get("capabilityType"), json.dumps(a.get("settings") or [], separators=(",",":")))
PY
  done
  api_get '/v1/certificates?limit=200' >"$tmp"
  python3 - "$tmp" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1]))
for item in payload.get("data", []):
    a=item.get("attributes", {})
    if a.get("activated", True):
        print("CERT", item.get("id"), a.get("certificateType"), a.get("displayName"), a.get("platform"), a.get("expirationDate"))
PY
  api_get '/v1/devices?limit=200' >"$tmp"
  python3 - "$tmp" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1]))
for item in payload.get("data", []):
    a=item.get("attributes", {})
    if a.get("status") == "ENABLED":
        udid=str(a.get("udid") or "")
        print("DEVICE", item.get("id"), a.get("name"), a.get("platform"), a.get("deviceClass"), ("…"+udid[-8:]) if udid else "")
PY
  rm -f "$tmp"
}

case "${1:-}" in
  doctor) doctor ;;
  bootstrap) bootstrap ;;
  *) echo "Usage: $0 doctor | bootstrap" >&2; exit 2 ;;
esac
