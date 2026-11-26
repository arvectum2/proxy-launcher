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
    private val durableMatches: (Map<String,Any>) -> Boolean,
) {
    enum class Outcome { APPLIED, STALE, RESTORED, BUSY, UNAVAILABLE, RECOVERY_REQUIRED }

    fun execute(expected: Map<String,Any>, patch: Map<String,Any?>,
                allowed: () -> Boolean): Outcome {
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
            if (!lease.beginMutation()) return@use Outcome.RECOVERY_REQUIRED
            val target = expected.toMutableMap().apply {
                patch.forEach { (k,v) -> if (v == null) remove(k) else put(k,v) }
            }
            val outcome = ManagedPreferenceTransaction(backend).execute(expected,patch,::permitted)
            val verified = when(outcome) {
                ManagedPreferenceTransaction.Outcome.APPLIED -> target
                ManagedPreferenceTransaction.Outcome.STALE, ManagedPreferenceTransaction.Outcome.RESTORED -> expected
                ManagedPreferenceTransaction.Outcome.RECOVERY_REQUIRED -> return@use Outcome.RECOVERY_REQUIRED
            }
            if (!lease.resolve { permitted() && durable(verified) })
                return@use Outcome.RECOVERY_REQUIRED
            when(outcome) {
                ManagedPreferenceTransaction.Outcome.APPLIED -> Outcome.APPLIED
                ManagedPreferenceTransaction.Outcome.STALE -> Outcome.STALE
                ManagedPreferenceTransaction.Outcome.RESTORED -> Outcome.RESTORED
                ManagedPreferenceTransaction.Outcome.RECOVERY_REQUIRED -> Outcome.RECOVERY_REQUIRED
            }
        }
    }
}
