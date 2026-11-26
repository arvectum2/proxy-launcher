# Tasks
- [x] M1/M2 pure ownership and change planner (ownership is only modeled, not persisted)
- [x] M3 one-shot review and inverse plan (pure core)
- [x] M4 encrypted bounded journal codec and synthetic restore tests
- [ ] Integrate ownership assignment/detach, exact-state store adapter, transactional profile and journal commit/failure recovery, explicit UI and rollback
- [ ] Exact-head CI for core; protected integration, later full storage/UI CI and separate real-device gate

Local: JVM 51/51, including 10 new methods for managed review and AES-GCM journal; 30 unique Python source contracts, git diff check PASS. This PR intentionally has no live profile writes or user-facing managed mode. No previous configuration has been established as working by a connectivity test. Journal stores only changed rows and exact post-state fingerprint; software-key tests only. Before enabling storage, verify process/lifecycle guard, actual Keystore, commit failure and recovery. Existing additive subscriptions remain unchanged.
