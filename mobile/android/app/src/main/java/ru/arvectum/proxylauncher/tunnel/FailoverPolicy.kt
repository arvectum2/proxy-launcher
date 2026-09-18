package ru.arvectum.proxylauncher.tunnel

import ru.arvectum.proxylauncher.model.PrimaryRestorePolicy

data class FailoverTuning(
    val failureThreshold: Int = 3,
    val switchCooldownMs: Long = 20_000L,
    val recentlyFailedSuppressionMs: Long = 60_000L,
    val healthIntervalMs: Long = 6_000L,
    val backupScanIntervalMs: Long = 30_000L,
    val networkSettleMs: Long = 4_000L,
) {
    init {
        require(failureThreshold >= 1)
        require(switchCooldownMs >= 0)
        require(recentlyFailedSuppressionMs >= 0)
        require(healthIntervalMs > 0)
        require(backupScanIntervalMs >= healthIntervalMs)
        require(networkSettleMs >= 0)
    }
}

class FailoverPolicy(
    val tuning: FailoverTuning = FailoverTuning(),
) {
    fun failureConfirmed(consecutiveFailures: Int): Boolean =
        consecutiveFailures >= tuning.failureThreshold

    fun cooldownElapsed(nowMs: Long, lastSwitchAtMs: Long): Boolean =
        lastSwitchAtMs <= 0L || nowMs - lastSwitchAtMs >= tuning.switchCooldownMs

    fun recentlyFailedStillSuppressed(
        nowMs: Long,
        failedAtMs: Long,
    ): Boolean =
        failedAtMs > 0L && nowMs - failedAtMs < tuning.recentlyFailedSuppressionMs

    /**
     * Auto policy:
     * 1. explicit primary;
     * 2. last successful Auto profile;
     * 3. remaining profiles in stable storage order;
     * 4. a recently failed profile is pushed to the end during the suppression window.
     */
    fun orderCandidates(
        profileIds: List<String>,
        primaryId: String?,
        lastSuccessfulId: String?,
        recentlyFailedId: String?,
    ): List<String> {
        if (profileIds.isEmpty()) return emptyList()
        val available = profileIds.distinct()
        val preferred = buildList {
            primaryId?.takeIf(available::contains)?.let(::add)
            lastSuccessfulId?.takeIf(available::contains)?.let(::add)
            addAll(available)
        }.distinct().toMutableList()

        if (recentlyFailedId != null && preferred.remove(recentlyFailedId)) {
            preferred.add(recentlyFailedId)
        }
        return preferred
    }

    fun shouldRestorePrimary(
        policy: PrimaryRestorePolicy,
        currentProfileId: String?,
        primaryProfileId: String?,
        primaryAvailable: Boolean,
        nowMs: Long,
        lastSwitchAtMs: Long,
    ): Boolean =
        policy == PrimaryRestorePolicy.RETURN_TO_PRIMARY &&
            primaryAvailable &&
            primaryProfileId != null &&
            currentProfileId != null &&
            currentProfileId != primaryProfileId &&
            cooldownElapsed(nowMs, lastSwitchAtMs)
}
