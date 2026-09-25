# Persistent App Store Connect release authentication

APL release uploads use one persistent App Store Connect **Team API key**
stored only on the Mac mini. Routine build validation/upload must not depend
on Apple Account SMS 2FA or an app-specific password.

## Local-only files

Private key:
`~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`

Local config:
`~/.config/arvectum/appstore-connect.env`

Required permissions:
- key directories: `700`
- `.p8`: `600`
- local config: `600`

Never commit, print, paste, or transmit the contents of the `.p8` file.

## One-time bootstrap

1. In App Store Connect open Users and Access > Integrations > App Store Connect API.
2. Generate a Team key named `APL Release Bot` with **App Manager** access.
3. Download the `.p8` exactly once.
4. Move it to the private-key directory and apply the permissions above.
5. Create the local config with:
   - `ASC_KEY_ID`
   - `ASC_ISSUER_ID`
   - `ASC_XCODE` (current full Xcode path)
6. Run:
   `tools/appstore_connect_release.sh auth`

A successful provider listing proves API authentication without Apple ID,
password, SMS code, or app-specific password.

## Routine release commands

Validate an artifact:
`tools/appstore_connect_release.sh validate /path/to/app.ipa`

Upload an iOS IPA or macOS App Store package:
`tools/appstore_connect_release.sh upload /path/to/artifact`

Inspect local setup without exposing the private key:
`tools/appstore_connect_release.sh doctor`

The Team API key remains valid until revoked; do not rotate it per release.
Revoke and replace it if the private key is lost, exposed, or no longer needed.

## 2FA boundary

This workflow removes interactive Apple Account authentication from routine
API-supported release operations. Apple Account access can still be required
for account/legal actions such as agreements, legal-entity changes, some
compliance settings, membership administration, or other web-only actions.
The API key is not a recovery mechanism for the Apple Account itself.
