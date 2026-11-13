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
