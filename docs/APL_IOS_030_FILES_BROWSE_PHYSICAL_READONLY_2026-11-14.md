# APL iOS 0.3.0 — real-device Files Browse and synthetic simulator diagnosis

Date: 2026-11-14, Moscow (00:48–01:00). Scope: signed iPhone **read-only UI** and disposable simulator-only Files acceptance.

## Physical iPhone13 (real data protected)

- Mac mini CoreDevice reported original paired iPhone13 available over USB.
  iPhone Mirroring was foreground, visibly connected and operational with
  handset locked. No physical screen unlock, Xcode installation, profile
  data readout, Keychain access, VPN toggle, Apple account or radio setting
  changed.
- Read-only CoreDevice app inventory confirmed
  `ru.arvectum.proxylauncher.ios` version **0.3.0 (49)** already installed.
- Launched this *existing* installed APL and visually observed its normal
  dashboard with **Connect**, not Disconnect; selected existing profile
  unchanged. Read-only Profiles tab displayed **3/3** existing profiles.
  Their addresses and authentication secrets were not recorded.
- Opened Settings and the standalone encrypted backup sheet, but did
  **not** create a new file or enter any backup password. Opened
  `Выбрать файл .aplbackup` in system Files, observed both **Recents**
  and **Browse → On My iPhone** functioning on real iPhone. No file was
  selected, decrypted or imported. Closed the document picker and backup
  sheet; returned the app to the dashboard with Connect shown.
- **This confirms only UI availability**, not an independently signed
  NetworkExtension VPN-OFF status, encrypted backup import or Keychain
  integrity receipt. No iPhone files or iCloud data were modified.

## Disposable iOS27 simulator

- Dedicated simulator: `APL-030-FilesQA-Clean-20261113`, runtime iOS27;
  source flag `DEBUG APL_RUN_EXPLICIT_FILES_QA`, QA-only fixture
  `apl-files-qa.invalid`, no actual subscriber or owner data.
- Previous signed simulator tests successfully wrote two 512-byte
  AES-GCM `.aplbackup` files through Files to **Local Storage File
  Provider**, but importer opened an empty **Recents**. The earlier
  Files roundtrip **XCTSkip did not accept restore**.
- New explicit diagnostic test
  `testInspectDisposableFilesBrowseNavigation` **PASS (33.504s)** and
  generated three screenshots (inside the local Xcode `.xcresult`):
  initial app backup form, **Browse → On My iPhone** showing both
  `.aplbackup` files, and Browse root. The files were present, 512 bytes
  each, even though the remote Files provider exposed no useful
  document filename through ordinary `XCUIApplication` descendant
  queries. This is the exact navigation gap, not missing ciphertext.
- The improved main QA test has a **simulator-only** coordinate fallback
  via Browse → On My iPhone → one synthetic file. It never reports a
  picker skip as a successful restore; it requires the import password field,
  authenticated AES-GCM decryption and exact idempotent receipt
  `Добавлено профилей: 0`.
- First rerun on previously used dedicated simulator, where other
  synthetic files existed: **1 full UI XCTest PASS / 0 skip / 0 failures**,
  35.134 seconds, using the known disposable password. This verifies
  UI selection, successful decryption and duplicate-safe restore; it
  does not by itself prove the selected file was exported by that same run.
- Stronger acceptance run created a **brand-new, previously unused iOS27
  iPhone13 simulator**
  `APL-030-FilesQA-Fresh-20261114` (UUID
  `06D9B441-B66A-444C-9EE7-F146D67D62CF`). The Files provider had
  **zero** pre-existing `.aplbackup` documents. The explicitly opted-in
  `testEncryptedFileCanBeSavedAndReimported` compiled with
  `DEBUG APL_RUN_EXPLICIT_FILES_QA` and local ad-hoc simulator signing
  **PASS (49.935s), 0 skip, 0 failures**. After the test the provider
  contained **exactly one** newly exported `.aplbackup` file,
  518 bytes, format v1 / PBKDF2-HMAC-SHA256 210000 iterations /
  16-byte salt / 264-byte AES-GCM combined ciphertext. No synthetic
  proxy address, profile name or QA password appeared in plaintext
  document bytes.
- On this fresh simulator the system Files picker selected the only
  exported file, the app accepted the same QA password and the
  existing synthetic profile restore returned precisely
  `Добавлено профилей: 0`. This **ACCEPTS the complete standalone
  Files UI roundtrip for synthetic simulator data**, not original
  account secrets or hardware network state.
- After the change, full **Swift Core250/250 PASS** and
  **iOS Python366 PASS + 1527 subtests**, including four dependency-free
  `unittest` source gates for explicit/isolated Files QA.

## Remaining acceptance

- **Simulator synthetic end-to-end backup acceptance: DONE.**
  **Original iPhone signed encrypted backup + Files restore acceptance:
  still pending owner-specific permission** to handle an encrypted
  artifact containing the user's real proxy credentials. Do not log,
  upload or copy plaintext secrets and never remove installed APL or
  overwrite existing profiles.
- Physical DNS/UDP/QUIC, Wi-Fi/LTE controlled handoff, Xray/WG/AWG
  native real egress, CloudKit 2-device and App Store 0.3.0 gates remain
  open. Do not conflate a Files picker view with VPN security acceptance.
