# Disposable Android managed-storage acceptance

This is a separate instrumentation APK (`ru.arvectum.apl.acceptance`), never the production package. It compiles the actual gate, process lease, XML verifier and authenticated recovery implementation directly from the checkout. No INTERNET permission, real source URLs, production app signing, installed app data or existing emulator snapshots are used. Fixture signing keys are generated in the disposable build directory. The original component probe is supplemented by StoreProbe (real profile and catalog stores) and VpnProbe (actual VPN service in a separate process, offline lifecycle only). The notification activity is a fixture, not the production UI; native library and INTERNET permission are deliberately absent.

## Build and run

Prerequisites: local Android SDK API 35, build-tools 36, cached Kotlin 2.0.21, JDK 17, and a **fresh disposable** ARM64 Android 36 AVD (separate AVD home, cold boot, `-no-snapshot`). Do not use a personal or production device. Use explicit serial throughout and verify the AVD name before installing. From repository root:

```sh
python3 mobile/android/tools/managed-acceptance/build.py /absolute/empty/disposable-build-dir
adb -s emulator-5580 emu avd name
adb -s emulator-5580 install /absolute/empty/disposable-build-dir/acceptance.apk
adb -s emulator-5580 shell am instrument -w -r ru.arvectum.apl.acceptance/.Probe
adb -s emulator-5580 shell am force-stop ru.arvectum.apl.acceptance
adb -s emulator-5580 shell am instrument -w -r -e phase after ru.arvectum.apl.acceptance/.Probe
adb -s emulator-5580 uninstall ru.arvectum.apl.acceptance
adb -s emulator-5580 emu kill
```

Check the named results and `result=PASS` for both phases, not just adb exit code. Phase one must run on fresh fixture data. Phase two intentionally leaves an unknown recovery marker, so do not reuse this app data; uninstall or discard the disposable AVD. No automatic marker cleanup. On a failed run preserve the bounded instrumentation output, stop only the explicitly identified disposable emulator, and investigate before retrying with fresh data.

## Acceptance evidence (2026-11-28, Mac mini, ARM64 API 36)

Source baseline: `bad6f33dd725cd16dc5dbedeb27b4d549174194a` (PR400, 15/15 CI). The final two-phase fixture returned `result=PASS` and instrumentation code 0 in each phase:

| Probe | Result |
| --- | --- |
| `xml_fsync` | PASS: actual Android SharedPreferences typed XML and file/directory force |
| `keystore` | PASS: real AndroidKeyStore AES/GCM, authenticated fingerprint and tamper rejection |
| `process_lease` | PASS: separate bound worker service, confirmed onDestroy, same process retained lease, process exit released it |
| `crash_recovery` | PASS: forced worker death after marker, exact BEFORE acknowledged once |
| `durable_change` | PASS: second process committed exact AFTER, persistent verifier matched it |
| `stale_cache_blocked` | PASS: default process cache still BEFORE, acknowledgement refused |
| `fresh_after_recovery` | PASS: fresh process cache matches disk, authenticates persisted key/marker and acknowledges AFTER |
| `mixed_fail_closed` | PASS: mixed state refused, marker retained, ordinary writes blocked |

These are emulator component acceptance results, not production or physical-device acceptance. Existing AVD data and real profiles were not touched.

## Actual stores and offline VPN lifecycle

On a fresh installation, run the store probe, then the VPN probe (the former leaves an empty pool). Use the same explicitly verified disposable emulator serial. Do not run after the component probe's mixed-state phase without uninstalling the fixture first.

```sh
adb -s emulator-5580 shell am instrument -w -r ru.arvectum.apl.acceptance/.StoreProbe
adb -s emulator-5580 shell am instrument -w -r ru.arvectum.apl.acceptance/.VpnProbe
```

Source baseline `982326e8f998bdf5a6d24c01fe336cd1c1481f43`, ARM64 API 36. Both phases returned result=PASS and instrumentation code 0.

| Probe | Result |
| --- | --- |
| catalog_encryption | PASS, authenticated source and exact persistent catalog, URL not plaintext |
| managed_import | PASS, real profile store and credential encryption, primary preserved |
| reviewed_update | PASS, consent required for old journal, one-shot confirmation |
| reviewed_rollback | PASS, old credential restored, journal removed |
| source_detach | PASS, old APIs reject owned row edit/delete, explicit consent, source removed after detach, profile/other source preserved |
| stale_catalog | PASS, changed catalog rejects captured fetch revision |
| first_import_rollback | PASS, selected first import blocked, deselected empty pool restored |
| vpn_empty_pool_stop | PASS, real foreground service exits safely with no profile |
| vpn_busy_denied | PASS, real service denied while common gate held, disk unchanged |
| vpn_pending_denied | PASS, real service denied with pending marker, disk unchanged and marker preserved |

VPN checks confirm terminal broadcast, removed notification, process exit and 3 exit records with no crash/ANR. Actual service and JNI wrapper sources compiled; no native library linked, no network permission, no tunnel established. This is not full VPN permission/revoke/network/engine acceptance. Production UI, physical device and power loss durability remain pending. The fixture contains synthetic catalog URLs only; no fetch occurs.

## Reviewed dialogs and localized outcomes

On a fresh fixture install run `adb -s emulator-5580 shell am instrument -w -r ru.arvectum.apl.acceptance/.DialogProbe`. This uses the actual reviewed dialog class and real stores in a fixture activity with lifecycle hooks; production MainActivity is not wired. On ARM64 API36, baseline `b997f1671ee8179991c0cd0997e8ef424f40a2aa`, all seven named checks passed (code 0): explicit apply, replacement consent, selection invalidation, onPause/onResume callback invalidation, rollback, detach, stale fetch ticket. The lifecycle callbacks were invoked by instrumentation; full OS background/foreground navigation is still pending. A fresh reinstall then passed StoreProbe 7/7 and VpnProbe 3/3 with localized busy/pending messages, three exit records, no crash/ANR. New messages are Russian/default and English; other locales use default fallback. Recovery and manual-edit dialog branches are compiled but not independently exercised. Native routing, real production UI and physical device remain pending.

## Extended dialog acceptance and localization repair

Baseline `e80e94bbe73a3f9f6ab2408edc88e50245c82f3d`, ARM64 API36: DialogProbe 10/10 named checks PASS, code 0. Seven earlier checks repeated; three additional checks passed: `dialog_manual_edit` (actual store atomic name edit plus detach, encrypted credential unchanged, source preserved), `dialog_recovery_ack` (authenticated exact BEFORE, ordinary write refused while marker exists, explicit acknowledgement removes blocker without changing disk), `dialog_os_background` (real moveTaskToBack, onPause observed, dialog dismissed and old ticket remains invalid after reorder-to-front/onResume). Production activity is not connected. No live source fetch, native routing or physical device tested. All 40 existing resource sets now contain 27 review strings; placeholder parity, AAPT2 compile/link, and exact-head CI 15/15 passed on localization commit. Translations are model-drafted and require linguistic/visual QA before release; no lint suppression.
