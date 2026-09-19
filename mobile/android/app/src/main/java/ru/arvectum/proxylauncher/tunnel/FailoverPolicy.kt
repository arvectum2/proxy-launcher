package ru.arvectum.proxylauncher.tunnel

/**
 * Pure policy for APL-MOB-002 continuous failover.
 *
 * Network I/O, credentials and Android lifecycle stay outside this class so the
 * anti-flapping rules can be tested deterministically. A failed observation is
 * only actionable after [failureThreshold] consecutive failures. Switches are
 * rate-limited by [switchCooldownMs]. Preferred-profile recovery is explicit:
 * stay on the current reserve, or return after [recoveryThreshold] consecutive
 * healthy observations.
 */
class FailoverPolicy(
    private val failureThreshold: Int = 2,
    private val recoveryThreshold: Int = 3,
    private val switchCooldownMs: Long = 30_000L,
    private val recoveryMode: RecoveryMode = RecoveryMode.STAY_ON_CURRENT,
) {
    init {
        require(failureThreshold >= 1)
        require(recoveryThreshold >= 1)
        require(switchCooldownMs >= 0)
    }

    private val consecutiveFailures = mutableMapOf<String, Int>()
    private val consecutiveSuccesses = mutableMapOf<String, Int>()
    private var lastSwitchAtMs: Long? = null

    fun observe(
        profileId: String,
        healthy: Boolean,
        nowMs: Long,
        activeProfileId: String,
        preferredProfileId: String?,
    ): Decision {
        require(nowMs >= 0)

        if (healthy) {
            consecutiveFailures[profileId] = 0
            val successes = (consecutiveSuccesses[profileId] ?: 0) + 1
            consecutiveSuccesses[profileId] = successes

            if (
                recoveryMode == RecoveryMode.RETURN_TO_PREFERRED &&
                preferredProfileId != null &&
                profileId == preferredProfileId &&
                activeProfileId != preferredProfileId &&
                successes >= recoveryThreshold &&
                cooldownElapsed(nowMs)
            ) {
                return Decision.RestorePreferred(preferredProfileId)
            }
            return Decision.None
        }

        consecutiveSuccesses[profileId] = 0
        val failures = (consecutiveFailures[profileId] ?: 0) + 1
        consecutiveFailures[profileId] = failures
        if (profileId != activeProfileId || failures < failureThreshold || !cooldownElapsed(nowMs)) {
            return Decision.None
        }
        return Decision.Failover(activeProfileId)
    }

    fun recordSwitch(nowMs: Long) {
        require(nowMs >= 0)
        lastSwitchAtMs = nowMs
        consecutiveFailures.clear()
        consecutiveSuccesses.clear()
    }

    fun reset() {
        consecutiveFailures.clear()
        consecutiveSuccesses.clear()
        lastSwitchAtMs = null
    }

    private fun cooldownElapsed(nowMs: Long): Boolean {
        val previous = lastSwitchAtMs ?: return true
        return nowMs - previous >= switchCooldownMs
    }

    enum class RecoveryMode {
        STAY_ON_CURRENT,
        RETURN_TO_PREFERRED,
    }

    sealed interface Decision {
        data object None : Decision
        data class Failover(val unavailableProfileId: String) : Decision
        data class RestorePreferred(val preferredProfileId: String) : Decision
    }
}
