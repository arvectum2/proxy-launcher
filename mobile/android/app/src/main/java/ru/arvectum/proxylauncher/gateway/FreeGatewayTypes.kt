package ru.arvectum.proxylauncher.gateway

import ru.arvectum.proxylauncher.model.ProxyProfile

data class FreeProxyLocation(
    val id: String,
    val label: String,
    val countryCode: String,
    val available: Boolean? = null,
    val latencyMs: Long? = null,
)

data class FreeProxySession(
    val profile: ProxyProfile,
    val password: String,
    val expiresAtEpochSeconds: Long,
)

object FreeSessionRefreshPolicy {
    fun delayMillis(nowEpochSeconds: Long, expiresAtEpochSeconds: Long): Long {
        val remainingSeconds = (expiresAtEpochSeconds - nowEpochSeconds).coerceAtLeast(0L)
        val marginSeconds = (remainingSeconds / 10L).coerceIn(MIN_MARGIN_SECONDS, MAX_MARGIN_SECONDS)
        return ((remainingSeconds - marginSeconds) * 1_000L).coerceAtLeast(MIN_DELAY_MS)
    }

    private const val MIN_MARGIN_SECONDS = 30L
    private const val MAX_MARGIN_SECONDS = 300L
    private const val MIN_DELAY_MS = 1_000L
}
