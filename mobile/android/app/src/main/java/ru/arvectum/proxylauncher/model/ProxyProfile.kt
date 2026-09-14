package ru.arvectum.proxylauncher.model

enum class ProxyType { SOCKS5, HTTP }

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
