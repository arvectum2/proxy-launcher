# Tasks
- [x] M1/M2 pure ownership and change planner (PR396 merged, 15/15 CI)
- [x] M3 one-shot review and inverse plan (pure core)
- [x] M4 encrypted bounded journal codec and synthetic restore tests
- [x] Storage sub-stage: strict preference snapshot, affected-key patch, SecureProfileStore adapter, synchronous commit + readback and simulated fault recovery (source, no UI activation)
- [x] Storage exact-head CI and protected merge (PR397, 15/15, 122ab905)
- [x] OS lock primitive, persistent pending marker and crash transaction coordinator; synthetic independent-JVM contention, forced exit and durability-proof tests
- [ ] Android disk verifier and fsync acceptance; actual default/VPN process integration, retained process/cache exclusion and explicit recovery of abandoned transaction. No UI activation until gates pass.
- [ ] Ownership detach on manual edit/source removal, explicit managed review/apply/rollback UI; safe handling of implicit primary and first import, no adoption of legacy rows
- [ ] Real-device Keystore, storage failure, crash recovery, network/lifecycle acceptance and full storage/UI CI before release

Local: JVM 61/61 including 10 new preference transaction/fault tests; 33 unique Python source contracts; actual SecureProfileStore source compiled against API35; git diff check PASS. Mock backend validates false/partial/lying commit, restore, stale state, gate loss and foreign-key preservation, not physical disk durability. SharedPreferences readback checks in-memory view, not ACID/fsync proof. Recovery latch currently only in-process; durable recovery and mutually exclusive tunnel start/mutation gate required before activation. Guard conservatively rejects changes to effective primary, including rollback of a first import if it became implicit primary. No real profiles changed. Existing additive mode unchanged.

Crash gate: 72 JVM tests (11 new), 36 unique Python contracts, Kotlin/API35 source compile, git diff check PASS. Real child JVM forcible termination leaves persistent marker; a second JVM is excluded even after a repeat local acquisition. Durable verifier is injected; actual SharedPreferences disk verification and OS power-loss durability not tested. Abandoned marker blocks subsequent mutation, not automatic restoration. No runtime participant wired; preserve live behavior.
