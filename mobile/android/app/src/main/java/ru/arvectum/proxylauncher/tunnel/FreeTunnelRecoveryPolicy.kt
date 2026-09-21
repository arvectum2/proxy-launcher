package ru.arvectum.proxylauncher.tunnel

data class FreeTunnelRecoveryDecision(
    val shouldRetry: Boolean,
    val windowStartedAtMs: Long,
    val attemptCount: Int,
)

object FreeTunnelRecoveryPolicy {
    fun decide(
        nowMs: Long,
        windowStartedAtMs: Long,
        attemptCount: Int,
    ): FreeTunnelRecoveryDecision {
        val windowExpired =
            windowStartedAtMs <= 0L ||
                nowMs < windowStartedAtMs ||
                nowMs - windowStartedAtMs > RETRY_WINDOW_MS
        val start = if (windowExpired) nowMs else windowStartedAtMs
        val nextCount = if (windowExpired) 1 else attemptCount.coerceAtLeast(0) + 1
        return FreeTunnelRecoveryDecision(
            shouldRetry = nextCount <= MAX_RETRIES_PER_WINDOW,
            windowStartedAtMs = start,
            attemptCount = nextCount,
        )
    }

    const val STABLE_RESET_MS = 60_000L
    internal const val RETRY_WINDOW_MS = 120_000L
    internal const val MAX_RETRIES_PER_WINDOW = 3
}
