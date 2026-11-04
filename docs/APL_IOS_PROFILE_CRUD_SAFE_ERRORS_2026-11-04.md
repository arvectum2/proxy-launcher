# iOS profiles: privacy-safe save/delete errors (4 November 2026)

## Defect and fix

The profile editor previously showed arbitrary Keychain or storage error
descriptions for failed save, single deletion and partial bulk deletion.
Those messages may include OSStatus and filesystem diagnostics.

ProfileMutationUX now displays bounded messages without system details:
- Save failures use existing Localizable "Не удалось сохранить профиль",
  translated in all 64 locales. Invalid host/port uses its existing 64-locale key.
- Bulk deletion failures use existing ProfileManagement
  "Не все профили удалены:" in 64 locales, removing the former trailing
  punctuation without appending an underlying NSError.
- VPN-off delete guard uses its existing ProfileManagement 64-locale key.
- Single deletion uses an accurate RU/EN safe fallback because no existing
  64-locale singular-delete failure key is available.

ProfileStore CRUD, Keychain access, rollback, partial delete return IDs,
profile selection and VPN guard are all unchanged.

## Verification

- Five focused portable source/locale checks PASS, all relevant keys
  present in 64/64 locale catalogs.
- Full iOS Python: 138 tests, one skipped, zero failures.
- Swift Core 159/159 PASS.
- XcodeGen and unsigned ARM64 Simulator App+PacketTunnel BUILD PASS.
- Actual compiled app includes ProfileMutationUX.saveFailed symbol.
- No user iPhone, VPN/Keychain, Apple review or native PR #314 touched.
