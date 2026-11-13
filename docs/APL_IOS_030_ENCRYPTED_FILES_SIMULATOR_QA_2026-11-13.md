# APL iOS 0.3.0 — encrypted standalone Files backup, isolated simulator QA

Date: 2026-11-13 (Europe/Moscow). Scope: **simulator + source only**. No owner's iPhone, physical VPN, commercial proxy profile, owner Keychain, Apple entitlement or App Store release changed.

## Verified evidence

- Used a disposable iPhone 13 iOS 27.0 simulator, explicitly synthetic `-aplBackupFilesQA` launch fixture (`apl-files-qa.invalid`). The temporary QA profile and its Keychain value exist only on the simulator.
- Debug UI test requires `APL_RUN_EXPLICIT_FILES_QA`. The first unsigned simulator run crashed in `AppViewModel.init` while creating the fixture; local ad-hoc simulator signing with the app's existing entitlements resolved the startup crash. This unsigned-fixture failure does **not** demonstrate a production user crash.
- On the fresh simulator, the Files export produced an actual `APL-Profiles-Encrypted.aplbackup` in the simulator's File Provider Storage. The app displayed its successful export confirmation. The encrypted document was read **locally and without decryption**, 512 bytes with a strict JSON envelope: `arvectum.apl.encrypted-profiles` format v1, PBKDF2-HMAC-SHA256 with 210,000 iterations, 16-byte salt and 264-byte AES-GCM combined ciphertext. None of the synthetic host, profile name or password strings appeared as plaintext bytes.
- Independent Swift package `ProfileBackupTests` (7/7) + `ProfileBackupRestorePlanTests` (2/2): **9/9 PASS**. Source iOS Python regression: **340 tests + 1513 subtests PASS**.
- `EncryptedFilesRoundtripUITests.testEncryptedFileCanBeSavedAndReimported` on the fresh locally signed simulator: **1 XCTSkip, 0 failures** after successful export. The system document import UI opened in an empty **Recents** view and did not expose the newly created file in its accessible Recents list. The backing encrypted file actually exists. A separate screenshot/accessibility diagnostic confirmed that the remote picker UI is outside APL's normal XCUI hierarchy. This is a limitation of the current UI automation/result, **not proof** that the product cannot import from **Browse**.
- On the reused older simulator, the same static filename triggered an iOS **Replace Existing Item** alert. The system UI automation selected Stop, so that run was **3 XCTest failures**; it is not evidence of corrupted encryption. Clean, isolated test environments are mandatory for reproducible export QA.

## Unaccepted gate

**Full external Files picker export → select exact exported file → decrypt → restore is NOT accepted.** In particular, a successful `xcodebuild` exit with an XCTest **skip** must never be reported as a successful restore.

Next execute a controlled **Browse** selection on a clean dedicated simulator with a known retained encrypted file, or manually verify via the system picker. Confirm actual `Добавлено профилей: 0` on reimport of the same synthetic profile, plus separate wrong-password and no-overwrite checks. A signed physical iPhone standalone backup of the user's actual profiles (or a separate owner-approved QA device) requires owner-specific permission and must avoid logging credentials or changing saved profile metadata. Successful simulator codec tests do not replace physical Keychain/Files acceptance.

## Separate iOS 0.3.0 gates

PR #377 native engine fail-closed and PR #378 UDP leak witness both reached exact-head GitHub Actions **11/11 PASS** on 13.11.2026, but neither was merged into `main` in this stage. Physical DNS/UDP/QUIC and Wi-Fi/LTE loss/handoff, native Xray/WG/AWG, CloudKit two-device and App Store release decisions remain open.

## Backup Files hardening — 13 November, afternoon source stage

Two app-side issues revealed by the simulator experiments were addressed in the
same **isolated branch**, without changing the encrypted format or the saved
profile schema:

1. Each export now proposes a different
   `APL-Profiles-Encrypted-YYYYMMDD-HHMMSS-<UUID>.aplbackup` filename (UTC
   calendar timestamp, random UUID; no server or credential information).
   Repeating the export on the **same** QA simulator successfully created both
   the old file and a new timestamp/UUID-suffixed file. The earlier
   `Replace Existing Item` sheet did not reappear.
2. File import no longer uses unbounded `Data(contentsOf:)` to read
   untrusted File Provider URLs. `ProfileBackupCodec.readEncryptedFile(at:)`
   opens the scoped URL and reads chunks of at most 64 KiB, with a hard cap of
   `maxFileBytes + 1` (1 MiB + 1); both overlarge and truncated files fail
   validation. The existing security-scope start/stop remains unchanged.
   Legacy backups retain their original `.aplbackup` extension and format.

Offline checks (after this change): **230/230 Swift CoreTests PASS**,
**343 Python iOS tests + 1513 subtests PASS**, **3 dependency-free
`unittest` source gates PASS**. The unsigned generic iPhoneOS Release
App+PacketTunnel build **SUCCEEDED**. Locally signed UI XCTest on the same
disposable iOS 27 simulator **TEST SUCCEEDED with 1 XCTSkip / 0 failures**:
the new export finished and produced a separate on-disk encrypted file, but
the third-party system Files **Recents** view still did not expose the file
for importing. **Do not count this result as a successful restore.**

Headless Xcode CLI has no graphical `Simulator.app` on the Mac mini, so
interactive tapping through the system Browse tab could not be performed
there. A full signed Files Browse import remains an **open acceptance gate**,
not a production regression and not a permission to overwrite user data.
