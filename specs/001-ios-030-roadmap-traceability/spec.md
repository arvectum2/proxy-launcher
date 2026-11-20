# APL iOS 0.3.0 — specification linkage candidate

Draft, source main 67df7e205ff63703bde90809e89f06211ec0d870. Existing active iOS roadmap and unified release plan remain authoritative; owner decision 11.11.2026 pauses other product development. No new feature, release, platform resumption or automatic execution authority.

## Requirements and acceptance source
- APL-SDD-R01: Preserve every existing requirement, task, local gate and historical entry from the active roadmap, unified release plan, general roadmap, local backlog and executor records. Existing APL IDs remain unchanged; reconcile duplicates, not delete them.
- APL-SDD-R02: One explicit iOS 0.3.0 candidate with truthful list of enabled capabilities; verify each against the unified release plan's original criteria. No unsupported transport advertised.
- APL-SDD-R03: Preserve profiles, identifiers, selected proxy, Keychain, groups, exclusions and backup/upgrade integrity to the extent required by the original release plan. Link each exact physical/signed build artifact and its remaining gates.
- APL-SDD-R04: Verify real PacketTunnel egress, relevant IPv4/IPv6/DNS/UDP/network changes and separate Smart4 receipts, only within admitted tests. Recorded debug experiments do not prove all production transport gates. Existing non-iOS/Smart4/native FIN/VLESS/WG/CloudKit constraints remain.
- APL-SDD-R05: No public release without signed-build checks, physical acceptance and applicable owner approval; missing/failed evidence remains open. Do not modify existing commercial profiles or live services without separate permission.

Sources (pinned main): [active roadmap](../../docs/APL_ACTIVE_IOS_ROADMAP_2026-11-11.md), [unified release plan](../../docs/APL_IOS_030_UNIFIED_RELEASE_2026-11-11.md), [general roadmap](../../docs/ROADMAP.md), [local backlog](../../docs/LOCAL_EXECUTION_BACKLOG.md), [checkpoint](../../.agent/current-task.yaml), [filtered queue](../../.agent/execution-queue.yaml). These define exact scope; this is a linkage layer, not a replacement.
