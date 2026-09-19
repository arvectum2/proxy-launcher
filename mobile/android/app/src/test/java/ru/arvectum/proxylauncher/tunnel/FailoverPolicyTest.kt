package ru.arvectum.proxylauncher.tunnel

import org.junit.Assert.assertEquals
import org.junit.Test

class FailoverPolicyTest {
    @Test
    fun transientFailureDoesNotSwitch() {
        val policy = FailoverPolicy(failureThreshold = 2, switchCooldownMs = 30_000)

        assertEquals(
            FailoverPolicy.Decision.None,
            policy.observe("a", healthy = false, nowMs = 1_000, activeProfileId = "a", preferredProfileId = "a"),
        )
        assertEquals(
            FailoverPolicy.Decision.None,
            policy.observe("a", healthy = true, nowMs = 2_000, activeProfileId = "a", preferredProfileId = "a"),
        )
    }

    @Test
    fun confirmedActiveFailureRequestsFailover() {
        val policy = FailoverPolicy(failureThreshold = 2, switchCooldownMs = 30_000)

        policy.observe("a", healthy = false, nowMs = 1_000, activeProfileId = "a", preferredProfileId = "a")
        assertEquals(
            FailoverPolicy.Decision.Failover("a"),
            policy.observe("a", healthy = false, nowMs = 2_000, activeProfileId = "a", preferredProfileId = "a"),
        )
    }

    @Test
    fun cooldownSuppressesImmediateSecondSwitch() {
        val policy = FailoverPolicy(failureThreshold = 1, switchCooldownMs = 30_000)
        assertEquals(
            FailoverPolicy.Decision.Failover("a"),
            policy.observe("a", healthy = false, nowMs = 1_000, activeProfileId = "a", preferredProfileId = "a"),
        )
        policy.recordSwitch(1_000)

        assertEquals(
            FailoverPolicy.Decision.None,
            policy.observe("b", healthy = false, nowMs = 20_000, activeProfileId = "b", preferredProfileId = "a"),
        )
        assertEquals(
            FailoverPolicy.Decision.Failover("b"),
            policy.observe("b", healthy = false, nowMs = 31_000, activeProfileId = "b", preferredProfileId = "a"),
        )
    }

    @Test
    fun stayCurrentModeDoesNotFailBack() {
        val policy = FailoverPolicy(
            recoveryThreshold = 2,
            recoveryMode = FailoverPolicy.RecoveryMode.STAY_ON_CURRENT,
        )

        repeat(3) { index ->
            assertEquals(
                FailoverPolicy.Decision.None,
                policy.observe("a", healthy = true, nowMs = 10_000L + index, activeProfileId = "b", preferredProfileId = "a"),
            )
        }
    }

    @Test
    fun returnPreferredModeRequiresStableRecovery() {
        val policy = FailoverPolicy(
            recoveryThreshold = 3,
            switchCooldownMs = 30_000,
            recoveryMode = FailoverPolicy.RecoveryMode.RETURN_TO_PREFERRED,
        )
        policy.recordSwitch(1_000)

        assertEquals(
            FailoverPolicy.Decision.None,
            policy.observe("a", healthy = true, nowMs = 31_000, activeProfileId = "b", preferredProfileId = "a"),
        )
        assertEquals(
            FailoverPolicy.Decision.None,
            policy.observe("a", healthy = true, nowMs = 32_000, activeProfileId = "b", preferredProfileId = "a"),
        )
        assertEquals(
            FailoverPolicy.Decision.RestorePreferred("a"),
            policy.observe("a", healthy = true, nowMs = 33_000, activeProfileId = "b", preferredProfileId = "a"),
        )
    }

    @Test
    fun inactiveFailureNeverTriggersFailover() {
        val policy = FailoverPolicy(failureThreshold = 1)
        assertEquals(
            FailoverPolicy.Decision.None,
            policy.observe("b", healthy = false, nowMs = 1_000, activeProfileId = "a", preferredProfileId = "a"),
        )
    }
}
