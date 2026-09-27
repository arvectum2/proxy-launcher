package ru.arvectum.proxylauncher.model

import java.util.UUID

/**
 * Client-visible managed transport profile issued by Arvectum.
 *
 * This is deliberately separate from ProxyProfile: manual HTTP/HTTPS/SOCKS
 * profiles keep their existing storage and behavior while managed products
 * can evolve without leaking upstream supplier credentials into the client.
 */
data class ManagedProxyProfile(
    val id: String,
    val name: String,
    val host: String,
    val port: Int,
    val credentialId: String,
    val serverName: String,
    val realityPassword: String,
    val realityShortId: String,
    val fingerprint: String = "chrome",
) {
    init {
        require(id.isNotBlank()) { "Managed profile id must not be blank" }
        require(name.isNotBlank()) { "Managed profile name must not be blank" }
        require(host.isNotBlank()) { "Managed profile host must not be blank" }
        require(port in 1..65535) { "Managed profile port must be between 1 and 65535" }
        require(runCatching { UUID.fromString(credentialId) }.isSuccess) {
            "Managed VLESS credential must be a UUID"
        }
        require(serverName.isNotBlank()) { "REALITY server name must not be blank" }
        require(realityPassword.isNotBlank()) { "REALITY password must not be blank" }
        require(realityShortId.length <= 16 && realityShortId.length % 2 == 0) {
            "REALITY short id must contain an even number of up to 16 hex characters"
        }
        require(realityShortId.all { it.digitToIntOrNull(16) != null }) {
            "REALITY short id must be hexadecimal"
        }
        require(fingerprint.isNotBlank()) { "REALITY fingerprint must not be blank" }
    }
}
