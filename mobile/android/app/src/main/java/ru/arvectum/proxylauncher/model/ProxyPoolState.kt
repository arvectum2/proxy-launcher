package ru.arvectum.proxylauncher.model

enum class ProxyHealthStatus {
    UNKNOWN,
    CHECKING,
    AVAILABLE,
    UNAVAILABLE,
}

enum class PrimaryRestorePolicy {
    STAY_ON_CURRENT,
    RETURN_TO_PRIMARY,
}

data class ProxyHealthSnapshot(
    val profileId: String,
    val status: ProxyHealthStatus,
    val latencyMs: Long?,
    val checkedAtMs: Long,
)

data class ProxyPoolEvent(
    val timestampMs: Long,
    val type: String,
    val profileId: String?,
    val profileName: String?,
    val detail: String?,
)
