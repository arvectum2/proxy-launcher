# Tasks
- [x] M1/M2 pure ownership and change planner (PR396 merged, 15/15 CI)
- [x] M3 one-shot review and inverse plan (pure core)
- [x] M4 encrypted bounded journal codec and synthetic restore tests
- [x] Storage sub-stage: strict preference snapshot, affected-key patch, SecureProfileStore adapter, synchronous commit + readback and simulated fault recovery (source, no UI activation)
- [x] Storage exact-head CI and protected merge (PR397, 15/15, 122ab905)
- [x] OS lock primitive, persistent pending marker and crash transaction coordinator; synthetic independent-JVM contention, forced exit and durability-proof tests
- [x] Crash gate core CI and protected merge (PR398, 15/15, d1bd0af8)
- [x] Strict persistent XML verifier, authenticated pre/post fingerprints, explicit expiring recovery acknowledgement for exactly recognized state, integrated dormant storage adapter; synthetic real-file tests PASS
- [ ] Disk/recovery exact-head CI and protected integration
- [ ] Actual default/VPN process participation and retained process/cache exclusion; device fsync, actual Android SharedPreferences format, crash/Keystore/lifecycle acceptance. Unknown/partial state stays blocked; separately design authenticated recovery of partial state. No UI activation until gates pass.
- [ ] Ownership detach on manual edit/source removal, explicit managed review/apply/rollback UI; safe handling of implicit primary and first import, no adoption of legacy rows
- [ ] Real-device Keystore, storage failure, crash recovery, network/lifecycle acceptance and full storage/UI CI before release

Local: JVM 61/61 including 10 new preference transaction/fault tests; 33 unique Python source contracts; actual SecureProfileStore source compiled against API35; git diff check PASS. Mock backend validates false/partial/lying commit, restore, stale state, gate loss and foreign-key preservation, not physical disk durability. SharedPreferences readback checks in-memory view, not ACID/fsync proof. Recovery latch currently only in-process; durable recovery and mutually exclusive tunnel start/mutation gate required before activation. Guard conservatively rejects changes to effective primary, including rollback of a first import if it became implicit primary. No real profiles changed. Existing additive mode unchanged.

Crash gate: 72 JVM tests (11 new), 36 unique Python contracts, Kotlin/API35 source compile, git diff check PASS. Real child JVM forcible termination leaves persistent marker; a second JVM is excluded even after a repeat local acquisition. Durable verifier is injected; actual SharedPreferences disk verification and OS power-loss durability not tested. Abandoned marker blocks subsequent mutation, not automatic restoration. No runtime participant wired; preserve live behavior.

Disk/recovery local gate: JVM81/81 (9 new), 39 unique Python source contracts, actual storage Kotlin/API35 compilation, git diff check PASS. Strict XML primitive map and set, exact typed equality, bounds, file + directory force, backup/symlink rejection. Authenticated pre/post fingerprints in marker, one-shot explicit acknowledgement only when durable state and exact marker remain unchanged; no profile rewrite. Synthetic real XML file backend verifies cache-only success remains blocked. Android actual filesystem/cache, key persistence, VPN participant and crash acceptance not tested. Unrecognized mixed state remains blocked; no automatic repair. Existing additive mode unchanged.

VPN participant candidate: shared gate before VPN preference construction; process-lifetime lease retained across service destruction/recreation; fail-closed denied start, no managed UI activation. 83 JVM tests, 41 Python Android contracts PASS; independent JVM retention/exit tested. Full Android CI, physical service/foreground/lock and cache/FS behavior remain pending; no attached adb device. Do not claim default-process ordinary writes are serialized by this change.

Ownership/first-import candidate: pure source detach and manual-edit patch; no runtime manual edit/catalog deletion wiring. Authenticated persisted journal first-import rollback exception for empty prior pool with no selection and Auto disabled. Prior PR400 head 67cd09e3 CI 15/15; new head needs CI. Local 90 JVM, 41 Android Python contracts and API35 store compile PASS. Policy for mixed crash state remains fail-closed, no rewrite.
