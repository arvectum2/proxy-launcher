# iOS 0.3.0 — CloudKit manual-exclusion review consistency

Date: 13 November 2026. Source-only safety stage. No iCloud account,
CloudKit container entitlement, saved profiles, credentials or real
NetworkExtension was modified.

## Scope and observed review hazard

The optional `ExclusionCloudSyncView` already exposed manual-only
exclusion previews and the `ExclusionCloudKitService` used an optimistic
concurrency write (`CKModifyRecords.ifServerRecordUnchanged`).

However, two confirmation paths were incomplete:

1. **Apply cloud to device.** The user could preview one remote snapshot,
   another device could edit its CloudKit record, and the first device could
   then apply an outdated list locally without reading the changed record.
2. **Upload device to cloud.** The user could preview the current device
   list, edit that list, then confirm the old cloud upload dialog. The old
   implementation uploaded the mutable model's *new* list, not the list
   displayed at the earlier review.

Neither path may change VPN routes without a fresh, user-understood review.

## Implementation and guarantees

- `ExclusionSyncContract.localUnchanged(previewed:current:)` compares a
  canonical, validated approved list with the current normalized list.
  Invalid/wildcard or modified lists fail closed; harmless duplicate or
  case changes remain semantically equal.
- `remoteUnchanged(previewed:current:previewTag:currentTag:)` compares
  remote payload equality and nonempty CloudKit `recordChangeTag`.
- Before applying a remote list, the view re-reads the private CK record,
  checks the exact fixed record ID, change tag, and payload, and rechecks
  local state after the await. A mismatch **refuses to mutate local rules**
  and requires a new manual preview.
- Before upload, the view refuses if local rules differ from the preview,
  then sends `localAtPreview` rather than mutable
  `model.manualExclusions`. The CloudKit service independently re-reads
  the remote version and retains `.ifServerRecordUnchanged` on write.
- Both operations clear `checked` after completion, error, or stale state
  and require a new review on subsequent operations.

This is a *best-effort last-read guard* for remote-to-device application;
another device could still write during the narrow interval after the
last remote read. A CloudKit record's optimistic CAS is enforced on
**cloud writes**, not on local iPhone storage writes. Physical two-device
acceptance with forced concurrent edits remains required.

## Verification

- Swift CoreTests: three additional cases exercise unchanged same-version
  acceptance; removal, addition and wildcard rejection; same payload
  with changed tag; replaced payload with retained tag; absent/empty
  version tags. Full Swift Core suite: **244/244 PASS**.
- iOS Python source tests: new four dependency-free `unittest` gates and
  updated legacy CloudKit rollback/consent contract. Full iOS suite:
  **361 PASS + 1527 subtests**.
- Generic unsigned iPhoneOS Release and ARM64 iOS Simulator Debug with
  `APL_CLOUDKIT_ENABLED` explicitly defined: **both BUILD SUCCEEDED**. The production `project.yml` still does **not** define the
  feature flag, and the app entitlements contain **no** CloudKit
  entitlement. Building code with the flag is not equivalent to running
  or authorizing iCloud sync.

## Remaining acceptance

- Enable private CloudKit container + provisioning only after Apple
  capability review and the product owner's explicit approval.
- Test two separate Apple devices with different locally modified
  manual-only exclusion lists, deleted/modified remote records,
  stale change tags, account sign-out, network loss, and safe rollback.
- Independently prove profiles, auth, Keychain, Smart3 evidence and
  PacketTunnel settings never enter the CloudKit payload.
- DNS/UDP/QUIC, Wi-Fi/LTE fail-closed, native VLESS/WG/AWG, end-to-end
  Files Browse decryption/import and the one public iOS 0.3.0 release
  remain blocked on their own acceptance gates.

## Extra server-side stale-review guard and two-device rehearsal

Second source-only stage on the same integration branch:
- Existing-record **upload** now checks the reviewed CKRecord ID and type,
  decodes the *reviewed* payload, and compares that complete decoded snapshot
  against the freshly fetched private CloudKit record **and** two nonempty
  `recordChangeTag` values. Any missing, malformed, changed or unreviewed
  data requires a new explicit preview. The final cloud write continues
  using `savePolicy: .ifServerRecordUnchanged` for server-side compare-and-swap.
- Added `ExclusionCloudTwoDeviceSimulationTests` with an **in-memory fake
  private database**, two independently previewing clients and an atomic
  commit check. Six focused tests cover concurrent first creation, another
  device editing the record after preview, a write racing between preflight
  and commit, changed local exclusions and remote deletion, a new change tag
  with unchanged payload, and a corrupted remote payload.
- Updated source gates to require full reviewed-payload and record-type
  validation on upload. Standard-library `unittest` compatibility retained.

Offline evidence: **250/250 Swift CoreTests PASS**, **362 Python iOS tests +
1527 subtests PASS**, and **9/9 CloudKit-focused Python tests PASS**.
Full unsigned iPhoneOS Release App + PacketTunnel **BUILD SUCCEEDED** and
ARM64 iOS Simulator Debug with explicit `APL_CLOUDKIT_ENABLED` compiled
**BUILD SUCCEEDED**. No actual CloudKit entitlement was enabled.

**Important limitation:** the fake database is a deterministic contract
simulation, not a CloudKit network emulator. Actual per-account identity,
iCloud container provisioning, two different physical devices, race latency,
account sign-out, record deletion and CloudKit conflict handling still need
explicitly authorised integration tests. No iCloud data, Keychain, VPN
settings, signed iPhone, or App Store release was touched.
