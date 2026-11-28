package ru.arvectum.proxylauncher.ui

import ru.arvectum.proxylauncher.R
import ru.arvectum.proxylauncher.storage.ManagedCrashGate
import ru.arvectum.proxylauncher.storage.ManagedCrashTransaction

internal object ManagedReviewMessages {
    fun outcome(value: ManagedCrashTransaction.Outcome): Int = when(value) {
        ManagedCrashTransaction.Outcome.APPLIED -> R.string.managed_applied
        ManagedCrashTransaction.Outcome.STALE -> R.string.managed_stale
        ManagedCrashTransaction.Outcome.RESTORED -> R.string.managed_restored
        ManagedCrashTransaction.Outcome.BUSY -> R.string.managed_busy
        ManagedCrashTransaction.Outcome.UNAVAILABLE -> R.string.managed_unavailable
        ManagedCrashTransaction.Outcome.RECOVERY_REQUIRED -> R.string.managed_recovery_required
        ManagedCrashTransaction.Outcome.FOLLOWUP_UNCERTAIN -> R.string.managed_followup_uncertain
    }
    fun vpnDenied(status: ManagedCrashGate.Status): Int = when(status) {
        ManagedCrashGate.Status.BUSY -> R.string.managed_vpn_busy
        ManagedCrashGate.Status.RECOVERY_REQUIRED -> R.string.managed_vpn_pending
        else -> R.string.managed_vpn_storage
    }
}
