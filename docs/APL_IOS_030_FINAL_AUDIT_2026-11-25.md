# Final engineering audit — 25 November 2026

## Exact immutable candidate

Source afd7ace6d965302ba58ef44162e12bbe6cf9b5cd; 0.3.0(49) Release with CloudKit opt-in host only, public VLESS hold unchanged, no private QA flags. Pinned product Go and exact-DNS/no-tproxy Rust verifiers passed. Unsigned ARM64 with link maps passed, embedded provider equals standalone product. Host SHA256 e63543bb9b86e48e3d2a60b50728548090c4ee82f0581a0b86d00685cfa939d6, provider 9a44b945e292df2acb75cd96fe42afd9dcbdb47737ec96486a93447b821ba19c. Link maps: Go11/Rust214 archive members in provider, none in host; no tproxy-config member names or NativeLabHost. Exact archives, package lock and hashes in native-artifacts/ios-030-final-audit-current-20261125/audit-receipt.json. Link-map header parsed separately after whole-file UTF8 decoding failed; not complete symbol or package SBOM. Not signed, installed or uploaded. Since staging, a726889b changes only private staging tool/tests, no runtime source delta.

443 Swift, 462 Python and 87 subtests PASS, release preflight with mandatory RSYA PASS. Initial Python 458 PASS/3 FAIL due to stale assertions about private namespaces and stricter manager census. Corrected isolated staging allowlist (8 exact names, unknown namespace negative regression), scoped tests to ordinary versus explicit QA-only manager removal with exact owner guard; on-demand read-only empty-rules check, no configuration. No runtime change. Source ancestry QR share and safe connection diagnostics verified; not signed binary proof.

## Licenses

Rust exact-DNS dependency graph unchanged from no-tproxy: 141 components/250 original notices verified at stage. Missing tproxy-config attribution pertains to old archive, not selected graph. Go696 product packages vs prior audited697 (only AWG tuntest removed), same module identities/locks per accepted receipts, historical 71 notices and 3 MPL archives. Source graph and linkage evidence only; complete final linked SBOM, applicable corresponding-source delivery and public notices remain open. Prior source-review staging restriction respected; no new source-delivery kit or publication. Yandex/AppMetrica attribution present in About and historical listing drafts; exact terms/privacy assessment pending.

## Privacy and remaining gates

26 privacy manifests byte-identical to prior CloudKit build; seven declare collection, AppMetrica AdSupport linked DeviceID tracking; Yandex DeviceID/AdvertisingData. No proof of actual transmission. Public linked policy fetched, SHA256 304a246fa63cfe2e2685bd8be6ddc80d2b5fa9ad03fb98edb4a0eec8b5ea84b6, explicitly denies ads/SDKs. Apple 5.4 and 5.1/privacy label requirements material; no compliance conclusion from declarations alone. Draft updated with CloudKit scope; no policy/labels or mandatory RSYA changes. Need evidence/assessment resolving VPN-specific rule and accurate public policy/labels before submission.

- Guarded VLESS LAN/ordinary UI accepted; WAN/handoff deferred by owner, not PASS. Public VLESS OFF, separate final product activation decision required.
- CloudKit Development exchange two logical clients/one iPhone accepted; ordinary UI and same-account second device pending, public schema/activation separate. Prior VPN untouched.
- Encrypted standalone backup/migration supervised acceptance, remaining security, source/notice and privacy gates pending. No owner credential exports.
- PR383 draft stacks on qa/ios-030-files-browse-20261114; PR377/378 target main, DIRTY, neither head ancestor. PR377 engine exit gate/core tests/contract identical; PacketTunnel diverges, current generation invalidation/markUnexpectedExit/shouldCancelTunnel present. PR378 witness tool and two contracts identical; physical test file diverges with additional scenarios. No blind merge or cherry-pick. CI 802e466d 3 success/3 running at inspection, latest exact-head check required.
- No final signed unified candidate, public activation, production schema deployment, upload or main merge authorized. Engineering audit complete; release not cleared.
