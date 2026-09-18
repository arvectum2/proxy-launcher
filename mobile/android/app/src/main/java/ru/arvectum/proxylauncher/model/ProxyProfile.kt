package ru.arvectum.proxylauncher.model

/**
 * Upstream proxy transport.
 *
 * AUTO intentionally means "reuse the same endpoint credentials and detect a working
 * transport", not a routing rule. The UI remains engine-agnostic.
 */
enum class ProxyType {
    AUTO,
    HTTPS,
    HTTP,
    SOCKS5,
}

data class ProxyProfile(
    val id: String,
    val name: String,
    val host: String,
    val port: Int,
    val type: ProxyType,
    val username: String? = null,
    val passwordRef: String? = null,
) {
    init {
        require(host.isNotBlank()) { "Proxy host must not be blank" }
        require(port in 1..65535) { "Proxy port must be between 1 and 65535" }
    }
}
