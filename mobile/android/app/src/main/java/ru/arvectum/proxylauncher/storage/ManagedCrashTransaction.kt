package ru.arvectum.proxylauncher.storage

/**
 * Coordinates the OS lease, pending marker, and preference transaction.
 * The injected durable verifier MUST check persistent storage, not a cached read.
 * Until the Android disk verifier and VPN participant are installed, this remains
 * an offline-tested adapter and must not be connected to the UI.
 */
internal class ManagedCrashTransaction(
    private val gate: ManagedCrashGate,
    private val backend: ManagedPreferenceBackend,
    private val evidenceKey: () -> javax.crypto.SecretKey,
    private val durableMatches: (Map<String,Any>) -> Boolean,
) {
    enum class Outcome { APPLIED, STALE, RESTORED, BUSY, UNAVAILABLE, RECOVERY_REQUIRED, FOLLOWUP_UNCERTAIN }

    fun execute(expected: Map<String,Any>, patch: Map<String,Any?>,
                allowed: () -> Boolean): Outcome = executeInternal(expected,{ patch },allowed,null)

    /** Followup is called once under the same lease, only after durable profile verification.
     * Never restore detached profiles if the separate catalog outcome is uncertain. */
    fun executeThen(expected: Map<String,Any>, patch: Map<String,Any?>, allowed: () -> Boolean,
                    followup: () -> Boolean): Outcome = executeInternal(expected,{ patch },allowed,followup)

    /** Build encrypted patch only after acquiring exclusion and verifying the exact durable baseline. */
    fun executePrepared(expected: Map<String,Any>, allowed: () -> Boolean,
                        prepare: () -> Map<String,Any?>?): Outcome = executeInternal(expected,prepare,allowed,null)

    private fun executeInternal(expected: Map<String,Any>, prepare: () -> Map<String,Any?>?,
                allowed: () -> Boolean, followup: (() -> Boolean)?): Outcome {
        val acquisition = gate.acquire()
        val lease = acquisition.lease ?: return when(acquisition.status) {
            ManagedCrashGate.Status.BUSY -> Outcome.BUSY
            ManagedCrashGate.Status.RECOVERY_REQUIRED -> Outcome.RECOVERY_REQUIRED
            else -> Outcome.UNAVAILABLE
        }
        return lease.use {
            fun permitted() = runCatching(allowed).getOrDefault(false)
            fun durable(state: Map<String,Any>) =
                runCatching { durableMatches(state) }.getOrDefault(false)
            if (!permitted() || !runCatching { backend.read() == expected }.getOrDefault(false) ||
                !durable(expected)) return@use Outcome.STALE
            val patch = runCatching(prepare).getOrNull() ?: return@use Outcome.STALE
            if (!lease.isHeld() || !permitted() || !runCatching { backend.read() == expected }.getOrDefault(false) ||
                !durable(expected)) return@use Outcome.STALE
            val target = expected.toMutableMap().apply {
                patch.forEach { (k,v) -> if (v == null) remove(k) else put(k,v) }
            }
            fun finish(): Outcome {
                if (followup == null) return Outcome.APPLIED
                if (!permitted() || !lease.isHeld() || !durable(target) ||
                    !runCatching { backend.read() == target }.getOrDefault(false)) return Outcome.FOLLOWUP_UNCERTAIN
                return if (runCatching(followup).getOrDefault(false)) Outcome.APPLIED else Outcome.FOLLOWUP_UNCERTAIN
            }
            if (expected==target) return@use if (followup == null) Outcome.STALE else finish()
            val evidence = runCatching { ManagedRecoveryEvidence.create(expected,target).seal(evidenceKey()) }.getOrNull()
                ?: return@use Outcome.UNAVAILABLE
            if (!lease.beginMutation(evidence)) return@use Outcome.RECOVERY_REQUIRED
            val outcome = ManagedPreferenceTransaction(backend).execute(expected,patch,::permitted)
            val verified = when(outcome) {
                ManagedPreferenceTransaction.Outcome.APPLIED -> target
                ManagedPreferenceTransaction.Outcome.STALE, ManagedPreferenceTransaction.Outcome.RESTORED -> expected
                ManagedPreferenceTransaction.Outcome.RECOVERY_REQUIRED -> return@use Outcome.RECOVERY_REQUIRED
            }
            if (!lease.resolve { permitted() && durable(verified) })
                return@use Outcome.RECOVERY_REQUIRED
            when(outcome) {
                ManagedPreferenceTransaction.Outcome.APPLIED -> finish()
                ManagedPreferenceTransaction.Outcome.STALE -> Outcome.STALE
                ManagedPreferenceTransaction.Outcome.RESTORED -> Outcome.RESTORED
                ManagedPreferenceTransaction.Outcome.RECOVERY_REQUIRED -> Outcome.RECOVERY_REQUIRED
            }
        }
    }
}
