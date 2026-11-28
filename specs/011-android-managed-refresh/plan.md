# Plan
1. Implement pure bounded planner using opaque credential revisions and exact source ownership. Test collision, protected IDs, stale approval and rollback invariants.
2. Implement store adapter with encrypted rollback journal, explicit ownership attach/detach, single commit and failure restoration. Do not expose mutation until UI and tests are complete.
3. Integrate explicit review/apply/rollback controls, verify exact-head CI and separate device acceptance. Do not call an untested previous snapshot last-known-good.

## Storage sub-stage
Use a strict immutable preference snapshot and affected-key compare-and-commit patch, with injectable backend and fault tests. Persist ownership and encrypted journal with profile changes in the same commit. No UI activation until the separate-process VPN exclusion and source deletion/detach workflow are verified. SharedPreferences commit plus best-effort verified restoration is not a database ACID guarantee.

## Crash gate sub-stage
Use a stable never-deleted lock inode, nonblocking exclusive OS lock, durable marker created before any managed preference mutation, cleared only after verified durable outcome. Any abandoned or malformed marker blocks normal acquisition; explicit recovery must be separately designed, never infer success from in-memory readback. Test child JVM termination and independent process contention in disposable directories. VPN service integration must acquire before opening preferences and account for retained process/cache after service teardown. No activation until actual device acceptance.

## Ownership and recovery boundary
Manual edits of an owned row detach in the same preference patch; no endpoint-based readoption. Explicit source deletion must verify exact catalog identity, acquire a common exclusion lease, durably commit detach for all indexed rows, verify cache/disk agreement, and only then remove the catalog entry. If catalog removal fails or is uncertain, preserve detached profiles; do not auto-reattach or automatically repeat deletion. Unindexed ownership blocks deletion. The single global rollback journal becomes invalid after a detach or edit; before live invalidation, authenticate existing journal and disclose loss of prior rollback to the user. Ordinary profile writes must not bypass an unresolved marker.

First-import rollback exception: only authenticated persisted exact-post-state journal, original pool empty, all imported rows still owned by that source, no explicit active/primary/selected/last-auto/failed IDs, Auto disabled. All normal implicit primary protections remain. The current UI may select a newly imported row, which correctly blocks this exception until explicitly deselected through a future supported UI.

Partial/unknown crash state: block managed mutation and VPN acquisition; do not guess which keys are correct or rewrite from fingerprints. Preserve marker and evidence, report generic recovery-required without secrets. Exact before/after may be acknowledged only after authenticated review, durable cache/disk equality, and exclusive lease. A future separately specified authenticated restore or verified backup workflow is required for mixed states. No automatic repair or marker deletion.
