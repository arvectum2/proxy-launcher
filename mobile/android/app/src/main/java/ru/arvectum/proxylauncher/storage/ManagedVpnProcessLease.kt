package ru.arvectum.proxylauncher.storage

/** Retain the lease for the entire VPN process, not the Service instance.
 * SharedPreferences caches can outlive onDestroy; only process exit releases it.
 * Never expose the lease to callers or allow a service to close it.
 */
internal object ManagedVpnProcessLease {
    private var lease: ManagedCrashGate.Lease? = null

    @Synchronized
    fun enter(gate: ManagedCrashGate): ManagedCrashGate.Status {
        lease?.let { return if (it.isHeld()) ManagedCrashGate.Status.ACQUIRED else ManagedCrashGate.Status.UNAVAILABLE }
        val acquisition = gate.acquire()
        lease = acquisition.lease
        return acquisition.status
    }
}
