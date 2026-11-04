# iOS encrypted backup — safe localized errors (4 November 2026)

## Defect

ProfileBackupError already has seven clear, fixed error descriptions:
short backup password, malformed backup, wrong password/authentication
failure, too many profiles, encryption failure, incomplete rollback and
active VPN. All seven keys are translated in every one of the 64
ProfileManagement.strings catalogs.

ProfileBackupView previously called the generic Localizable lookup for these
keys, which do NOT exist in that table, and in other paths showed arbitrary
FileExporter / Files / Keychain / CryptoKit error descriptions to the user.
This could surface an untranslated Russian string or disclose local file
paths and internal error details.

## Fixed without changing stored data

- ProfileBackupUX maps known typed ProfileBackupError to
  AppL10n.tr(safeKey, table: ProfileManagement), using all 64 existing
  translations and retaining specific auth/invalid-file/partial-rollback
  guidance.
- Unclassified system errors receive a bounded, operation-specific safe
  message for save-file, read-file, encrypted backup creation or restore.
  English fallback is used for languages without a new localized generic
  platform error; Russian selection gets Russian wording. No system
  message or path, profile host, credential, password or error code is
  included.
- Existing cancellation of the Files exporter remains silent, and
  existing encrypted file size limits, security scope release, AES-GCM
  codec, VPN-off restore gate and partial rollback are untouched.
- No changed encryption parameters, profile migration, Keychain
  permissions, files, credentials or running VPN state.

## Verified

- Six focused Python contracts PASS, including each of the seven real
  backup keys in all 64 ProfileManagement locale files, no raw system
  descriptions, correct operation contexts and preserved user cancellation.
- Full iOS Python: 139 tests, one skipped, zero failures.
- Swift Core: 159/159 PASS, including existing backup restore-plan tests.
- XcodeGen and unsigned ARM64 iOS Simulator App+PacketTunnel build PASS.
- The actual compiled app debug.dylib has a Swift symbol for
  ProfileBackupUX.message(error:operation:).
- No physical iPhone installed, no real Keychain/profile data read or
  App Store submission changed.

This is a bounded privacy and localization fix, not a live-device
encrypted-backup end-to-end acceptance.
