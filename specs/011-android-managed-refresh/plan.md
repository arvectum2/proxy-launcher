# Plan
1. Implement pure bounded planner using opaque credential revisions and exact source ownership. Test collision, protected IDs, stale approval and rollback invariants.
2. Implement store adapter with encrypted rollback journal, explicit ownership attach/detach, single commit and failure restoration. Do not expose mutation until UI and tests are complete.
3. Integrate explicit review/apply/rollback controls, verify exact-head CI and separate device acceptance. Do not call an untested previous snapshot last-known-good.

## Storage sub-stage
Use a strict immutable preference snapshot and affected-key compare-and-commit patch, with injectable backend and fault tests. Persist ownership and encrypted journal with profile changes in the same commit. No UI activation until the separate-process VPN exclusion and source deletion/detach workflow are verified. SharedPreferences commit plus best-effort verified restoration is not a database ACID guarantee.

## Crash gate sub-stage
Use a stable never-deleted lock inode, nonblocking exclusive OS lock, durable marker created before any managed preference mutation, cleared only after verified durable outcome. Any abandoned or malformed marker blocks normal acquisition; explicit recovery must be separately designed, never infer success from in-memory readback. Test child JVM termination and independent process contention in disposable directories. VPN service integration must acquire before opening preferences and account for retained process/cache after service teardown. No activation until actual device acceptance.
