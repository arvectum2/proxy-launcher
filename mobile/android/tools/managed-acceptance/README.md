# Disposable Android managed-storage acceptance

This is a separate instrumentation APK (`ru.arvectum.apl.acceptance`), never the production package. It compiles the actual gate, process lease, XML verifier and authenticated recovery implementation directly from the checkout. No INTERNET permission, real source URLs, production app signing, installed app data or existing emulator snapshots are used. Fixture signing keys are generated in the disposable build directory. It does not test the real `ProxyVpnService`, `SecureProfileStore` or subscription catalog adapter.

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

These are emulator component acceptance results, not production or physical-device acceptance. Real VPN foreground-service permission/notification/stop behavior, actual store and catalog integration, real routing, power loss durability and physical device remain pending. Existing AVD data and real profiles were not touched.
