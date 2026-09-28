package ru.arvectum.proxylauncher.ads

object AdDisplayPolicy {
    const val GRACE_LAUNCHES = 2
    const val MIN_INTERVAL_MS = 4 * 60 * 60 * 1000L

    fun shouldAttempt(
        launchCount: Int,
        lastShownAtMs: Long,
        nowMs: Long,
    ): Boolean {
        if (launchCount <= GRACE_LAUNCHES) return false
        if (lastShownAtMs <= 0L) return true
        return nowMs - lastShownAtMs >= MIN_INTERVAL_MS
    }
}
