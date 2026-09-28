package ru.arvectum.proxylauncher.ads

object AppOpenAdPolicy {
    const val FIRST_LAUNCHES_WITHOUT_AD = 2
    const val MIN_INTERVAL_BETWEEN_ADS_MS = 4L * 60L * 60L * 1000L

    data class Decision(
        val launchCount: Int,
        val shouldAttemptAd: Boolean,
    )

    fun decide(
        previousLaunchCount: Int,
        lastAdShownAtMs: Long,
        nowMs: Long,
        debugBuild: Boolean,
    ): Decision {
        val launchCount = previousLaunchCount.coerceAtLeast(0) + 1
        if (debugBuild) {
            return Decision(launchCount, true)
        }

        val graceCompleted = launchCount > FIRST_LAUNCHES_WITHOUT_AD
        val cooldownCompleted =
            lastAdShownAtMs <= 0L ||
                nowMs - lastAdShownAtMs >= MIN_INTERVAL_BETWEEN_ADS_MS
        return Decision(
            launchCount = launchCount,
            shouldAttemptAd = graceCompleted && cooldownCompleted,
        )
    }
}
