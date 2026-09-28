package ru.arvectum.proxylauncher.ads

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppOpenAdPolicyTest {
    @Test
    fun debugBuildAttemptsAdImmediately() {
        val decision = AppOpenAdPolicy.decide(
            previousLaunchCount = 0,
            lastAdShownAtMs = 0L,
            nowMs = 1_000L,
            debugBuild = true,
        )

        assertTrue(decision.shouldAttemptAd)
        assertTrue(decision.launchCount == 1)
    }

    @Test
    fun releaseBuildSkipsFirstTwoLaunches() {
        val first = AppOpenAdPolicy.decide(0, 0L, 1_000L, false)
        val second = AppOpenAdPolicy.decide(1, 0L, 2_000L, false)
        val third = AppOpenAdPolicy.decide(2, 0L, 3_000L, false)

        assertFalse(first.shouldAttemptAd)
        assertFalse(second.shouldAttemptAd)
        assertTrue(third.shouldAttemptAd)
    }

    @Test
    fun releaseBuildHonorsFourHourCooldown() {
        val lastShown = 10_000L
        val tooSoon = AppOpenAdPolicy.decide(
            previousLaunchCount = 10,
            lastAdShownAtMs = lastShown,
            nowMs = lastShown + AppOpenAdPolicy.MIN_INTERVAL_BETWEEN_ADS_MS - 1,
            debugBuild = false,
        )
        val eligible = AppOpenAdPolicy.decide(
            previousLaunchCount = 11,
            lastAdShownAtMs = lastShown,
            nowMs = lastShown + AppOpenAdPolicy.MIN_INTERVAL_BETWEEN_ADS_MS,
            debugBuild = false,
        )

        assertFalse(tooSoon.shouldAttemptAd)
        assertTrue(eligible.shouldAttemptAd)
    }
}
