package ru.arvectum.proxylauncher.ads

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdDisplayPolicyTest {
    @Test
    fun firstTwoLaunchesAreAdFree() {
        assertFalse(AdDisplayPolicy.shouldAttempt(1, 0L, 10_000L))
        assertFalse(AdDisplayPolicy.shouldAttempt(2, 0L, 20_000L))
    }

    @Test
    fun thirdLaunchMayShowFirstAd() {
        assertTrue(AdDisplayPolicy.shouldAttempt(3, 0L, 30_000L))
    }

    @Test
    fun recentImpressionSuppressesAnotherAd() {
        val lastShown = 1_000_000L
        assertFalse(
            AdDisplayPolicy.shouldAttempt(
                launchCount = 10,
                lastShownAtMs = lastShown,
                nowMs = lastShown + AdDisplayPolicy.MIN_INTERVAL_MS - 1,
            ),
        )
    }

    @Test
    fun adMayShowAgainAfterInterval() {
        val lastShown = 1_000_000L
        assertTrue(
            AdDisplayPolicy.shouldAttempt(
                launchCount = 10,
                lastShownAtMs = lastShown,
                nowMs = lastShown + AdDisplayPolicy.MIN_INTERVAL_MS,
            ),
        )
    }
}
