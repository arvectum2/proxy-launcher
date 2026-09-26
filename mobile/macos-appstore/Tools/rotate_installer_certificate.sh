#!/bin/zsh
set -euo pipefail

[[ "${APL_ROTATE_INSTALLER_CERT:-}" == "1" ]] || {
  echo "Refusing to rotate Mac Installer Distribution certificate without APL_ROTATE_INSTALLER_CERT=1" >&2
  exit 2
}

ROOT=${0:A:h:h:h:h}
PROVISIONING="$ROOT/mobile/macos-appstore/Tools/appstore_provisioning.sh"
[[ -r "$PROVISIONING" ]] || { echo "Missing provisioning helper" >&2; exit 2; }

# Load only API/config helpers; do not execute the helper's command dispatcher.
source <(sed '/^case "/,$d' "$PROVISIONING")

WORK=$(mktemp -d /tmp/apl-installer-rotation.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
umask 077

openssl genrsa -out "$WORK/installer.key" 2048 >/dev/null 2>&1
openssl req -new \
  -key "$WORK/installer.key" \
  -out "$WORK/installer.csr" \
  -subj "/CN=Arvectum Mac Installer Distribution/O=LLC ARVECTUM/C=RU" >/dev/null 2>&1

csr=$(cat "$WORK/installer.csr")
payload=$(python3 - "$csr" <<'PY'
import json, sys
print(json.dumps({
    "data": {
        "type": "certificates",
        "attributes": {
            "certificateType": "MAC_INSTALLER_DISTRIBUTION",
            "csrContent": sys.argv[1],
        },
    }
}, separators=(",", ":")))
PY
)

# Try creation before revoking anything. If Apple permits it, keep the existing
# certificate untouched. A team normally has a single certificate of this type,
# so Apple commonly returns a limit/conflict response here.
token=$(make_token)
code=$(curl -sS -o "$WORK/create-first.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $token" \
  -H 'Content-Type: application/json' \
  -d "$payload" \
  'https://api.appstoreconnect.apple.com/v1/certificates')

if [[ "$code" == 2* ]]; then
  cp "$WORK/create-first.json" "$WORK/certificate.json"
  echo "Created a new installer certificate without revoking the prior certificate."
else
  if [[ "$code" != "409" && "$code" != "422" ]]; then
    echo "Installer certificate preflight failed before any revocation: HTTP $code" >&2
    python3 - "$WORK/create-first.json" <<'PY'
import json, sys
try: p=json.load(open(sys.argv[1]))
except Exception: raise SystemExit(0)
for e in p.get("errors", []):
    print(e.get("status"), e.get("code"), e.get("title"), e.get("detail"), file=sys.stderr)
PY
    exit 1
  fi

  current="$WORK/current.json"
  api_get '/v1/certificates?filter%5BcertificateType%5D=MAC_INSTALLER_DISTRIBUTION&limit=200' >"$current"
  current_id=$(python3 - "$current" <<'PY'
import json, sys
p=json.load(open(sys.argv[1]))
active=[x for x in p.get("data", []) if x.get("attributes", {}).get("activated", True)]
if len(active) != 1:
    raise SystemExit(f"Expected exactly one active Mac Installer Distribution certificate, found {len(active)}")
print(active[0]["id"])
PY
)
  echo "Rotating the single active Mac Installer Distribution certificate: $current_id"
  api_request DELETE "/v1/certificates/$current_id" >/dev/null
  api_request POST '/v1/certificates' "$payload" >"$WORK/certificate.json"
fi

python3 - "$WORK/certificate.json" "$WORK/installer.cer" "$WORK/meta.env" <<'PY'
import base64, json, pathlib, sys
p=json.load(open(sys.argv[1]))
d=p["data"]; a=d["attributes"]
pathlib.Path(sys.argv[2]).write_bytes(base64.b64decode(a["certificateContent"]))
pathlib.Path(sys.argv[3]).write_text(
    "ASC_INSTALLER_CERT_ID=" + d["id"] + "\n"
    "ASC_INSTALLER_CERT_SERIAL=" + (a.get("serialNumber") or "") + "\n"
    "ASC_INSTALLER_CERT_EXPIRES=" + (a.get("expirationDate") or "") + "\n"
)
print("CREATED", d["id"], a.get("serialNumber"), a.get("expirationDate"))
PY

openssl x509 -inform DER -in "$WORK/installer.cer" -out "$WORK/installer.pem"
fingerprint=$(openssl x509 -in "$WORK/installer.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)
echo "SHA1=$fingerprint"

KC="$HOME/.config/arvectum/appstore-installer.keychain-db"
PASS_FILE="$HOME/.config/arvectum/appstore-installer-keychain.pass"
STATE_FILE="$HOME/.config/arvectum/appstore-installer.env"

if [[ -e "$KC" ]]; then
  mv "$KC" "$KC.backup.$(date +%Y%m%d%H%M%S)"
fi

kcpass=$(openssl rand -hex 32)
printf '%s' "$kcpass" >"$PASS_FILE"
chmod 600 "$PASS_FILE"
security create-keychain -p "$kcpass" "$KC"
security set-keychain-settings -lut 21600 "$KC"

p12pass=$(openssl rand -hex 24)
openssl pkcs12 -export \
  -inkey "$WORK/installer.key" \
  -in "$WORK/installer.pem" \
  -out "$WORK/installer.p12" \
  -name "Arvectum Mac Installer Distribution" \
  -passout pass:"$p12pass" >/dev/null 2>&1

security import "$WORK/installer.p12" \
  -k "$KC" \
  -P "$p12pass" \
  -T /usr/bin/productbuild \
  -T /usr/bin/security \
  -T /usr/bin/codesign >/dev/null

security unlock-keychain -p "$kcpass" "$KC"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$kcpass" "$KC" >/dev/null

{
  cat "$WORK/meta.env"
  echo "ASC_INSTALLER_CERT_SHA1=$fingerprint"
  echo "ASC_INSTALLER_KEYCHAIN=$KC"
  echo "ASC_INSTALLER_KEYCHAIN_PASS_FILE=$PASS_FILE"
} >"$STATE_FILE"
chmod 600 "$STATE_FILE"

security list-keychains -d user -s \
  "$KC" \
  "$HOME/.config/arvectum/appstore-release.keychain-db" \
  "$HOME/Library/Keychains/login.keychain-db"

unset kcpass p12pass csr token
echo "Installer certificate rotation complete."
security find-identity -v "$KC" | grep '3rd Party Mac Developer Installer'
