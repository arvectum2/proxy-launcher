package ru.arvectum.proxylauncher.tunnel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import ru.arvectum.proxylauncher.model.PrimaryRestorePolicy

class FailoverPolicyTest {
    private val policy = FailoverPolicy(
        FailoverTuning(
            failureThreshold = 3,
            switchCooldownMs = 20_000,
            recentlyFailedSuppressionMs = 60_000,
            healthIntervalMs = 5_000,
            backupScanIntervalMs = 30_000,
            networkSettleMs = 4_000,
        ),
    )

    @Test
    fun failureRequiresThreeConsecutiveFailures() {
        assertFalse(policy.failureConfirmed(1))
        assertFalse(policy.failureConfirmed(2))
        assertTrue(policy.failureConfirmed(3))
    }

    @Test
    fun cooldownPreventsImmediateRepeatedSwitch() {
        assertFalse(policy.cooldownElapsed(nowMs = 25_000, lastSwitchAtMs = 10_000))
        assertTrue(policy.cooldownElapsed(nowMs = 30_000, lastSwitchAtMs = 10_000))
    }

    @Test
    fun recentlyFailedCandidateMovesBehindBackups() {
        assertEquals(
            listOf("backup-b", "backup-a", "primary"),
            policy.orderCandidates(
                profileIds = listOf("backup-b", "primary", "backup-a"),
                primaryId = "primary",
                lastSuccessfulId = "primary",
                recentlyFailedId = "primary",
            ),
        )
    }

    @Test
    fun primaryWinsNormalAutoOrdering() {
        assertEquals(
            listOf("primary", "backup-b", "backup-a"),
            policy.orderCandidates(
                profileIds = listOf("backup-a", "primary", "backup-b"),
                primaryId = "primary",
                lastSuccessfulId = "backup-b",
                recentlyFailedId = null,
            ),
        )
    }

    @Test
    fun restorePolicyRequiresCooldownAndPrimaryAvailability() {
        assertFalse(
            policy.shouldRestorePrimary(
                PrimaryRestorePolicy.STAY_ON_CURRENT,
                "backup",
                "primary",
                primaryAvailable = true,
                nowMs = 100_000,
                lastSwitchAtMs = 50_000,
            ),
        )
        assertFalse(
            policy.shouldRestorePrimary(
                PrimaryRestorePolicy.RETURN_TO_PRIMARY,
                "backup",
                "primary",
                primaryAvailable = true,
                nowMs = 60_000,
                lastSwitchAtMs = 50_000,
            ),
        )
        assertTrue(
            policy.shouldRestorePrimary(
                PrimaryRestorePolicy.RETURN_TO_PRIMARY,
                "backup",
                "primary",
                primaryAvailable = true,
                nowMs = 80_000,
                lastSwitchAtMs = 50_000,
            ),
        )
    }

    @Test
    fun networkTransitionRequiresSettleGrace() {
        assertFalse(policy.networkSettled(nowElapsedMs = 12_000, lastTransitionElapsedMs = 10_000))
        assertTrue(policy.networkSettled(nowElapsedMs = 14_000, lastTransitionElapsedMs = 10_000))
        assertTrue(policy.networkSettled(nowElapsedMs = 10_000, lastTransitionElapsedMs = 0))
    }

    @Test
    fun noSavedProfilesProducesNoCandidates() {
        assertEquals(
            emptyList<String>(),
            policy.orderCandidates(
                profileIds = emptyList(),
                primaryId = null,
                lastSuccessfulId = null,
                recentlyFailedId = null,
            ),
        )
    }

    @Test
    fun recentlyFailedSuppressionExpiresAtBoundary() {
        assertTrue(policy.recentlyFailedStillSuppressed(nowMs = 69_999, failedAtMs = 10_000))
        assertFalse(policy.recentlyFailedStillSuppressed(nowMs = 70_000, failedAtMs = 10_000))
    }
}
