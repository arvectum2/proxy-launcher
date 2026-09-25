package ru.arvectum.proxylauncher.tunnel

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FreeTunnelRecoveryPolicyTest {
    @Test
    fun allowsThreeRetriesInsideWindowThenStops() {
        val start = 10_000L
        val first = FreeTunnelRecoveryPolicy.decide(start, 0L, 0)
        val second = FreeTunnelRecoveryPolicy.decide(start + 10_000L, first.windowStartedAtMs, first.attemptCount)
        val third = FreeTunnelRecoveryPolicy.decide(start + 20_000L, second.windowStartedAtMs, second.attemptCount)
        val fourth = FreeTunnelRecoveryPolicy.decide(start + 30_000L, third.windowStartedAtMs, third.attemptCount)

        assertTrue(first.shouldRetry)
        assertTrue(second.shouldRetry)
        assertTrue(third.shouldRetry)
        assertFalse(fourth.shouldRetry)
        assertEquals(4, fourth.attemptCount)
    }

    @Test
    fun expiredWindowStartsFreshRetryBudget() {
        val decision = FreeTunnelRecoveryPolicy.decide(
            nowMs = 500_000L,
            windowStartedAtMs = 10_000L,
            attemptCount = 3,
        )
        assertTrue(decision.shouldRetry)
        assertEquals(500_000L, decision.windowStartedAtMs)
        assertEquals(1, decision.attemptCount)
    }
}
