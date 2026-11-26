package ru.arvectum.proxylauncher.model

import java.net.URI
import java.net.URLDecoder
import java.util.Locale

/** Ephemeral editor input, never persisted or logged by the parser. */
class ImportedProxy internal constructor(
    val host: String,
    val port: Int,
    val type: ProxyType,
    val username: String,
    val password: String,
    val name: String,
) {
    override fun toString() = "ImportedProxy(<redacted>)"
}

object ProxyImport {
    const val MAX_INPUT = 8192

    /** Null means invalid or unsupported. No errors include source text. */
    fun parse(input: String): ImportedProxy? {
        if (input.length > MAX_INPUT) return null
        val text = input.trim().removePrefix("\uFEFF").trim()
        if (text.isEmpty() || text.any { it.isISOControl() }) return null
        return try {
            if (text.contains("://")) parseUri(text) else parseSupplier(text)
        } catch (_: Exception) {
            null
        }
    }

    private fun parseUri(text: String): ImportedProxy? {
        val uri = URI(text)
        val type = when (uri.scheme?.lowercase(Locale.ROOT)) {
            "http" -> ProxyType.HTTP
            "https" -> ProxyType.HTTPS
            "socks5", "socks5h", "socks" -> ProxyType.SOCKS5
            else -> return null
        }
        if (uri.rawQuery != null || uri.rawPath !in listOf("", "/")) return null
        val host = uri.host ?: return null
        val credentials = uri.rawUserInfo?.split(':', limit = 2)
        val user = credentials?.firstOrNull()?.let(::decode) ?: ""
        val pass = credentials?.getOrNull(1)?.let(::decode) ?: ""
        return item(host, uri.port.toString(), type, user, pass, uri.fragment.orEmpty())
    }

    private fun parseSupplier(text: String): ImportedProxy? {
        val end = if (text.startsWith("[")) {
            val close = text.indexOf(']')
            if (close < 0 || text.getOrNull(close + 1) != ':') return null
            close + 1
        } else text.indexOf(':')
        if (end <= 0) return null
        val host = text.substring(0, end)
        val parts = text.substring(end + 1).split(':', limit = 3)
        if (parts.size != 1 && parts.size != 3) return null
        return item(host, parts[0], ProxyType.HTTP, parts.getOrNull(1).orEmpty(),
            parts.getOrNull(2).orEmpty(), "")
    }

    private fun decode(raw: String): String =
        URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8")

    private fun item(rawHost: String, portText: String, type: ProxyType,
                     user: String, pass: String, label: String): ImportedProxy? {
        if (portText.isEmpty() || portText.any { it !in '0'..'9' }) return null
        val port = portText.toIntOrNull()?.takeIf { it in 1..65535 } ?: return null
        if (rawHost.isEmpty() || rawHost.any { it.isWhitespace() || it.isISOControl() ||
                it in "/@?#%\\\""
            }) return null
        val parsed = URI("http://$rawHost:$port")
        if (parsed.host != rawHost || parsed.port != port || parsed.rawUserInfo != null ||
            parsed.rawPath != "" || parsed.rawQuery != null || parsed.rawFragment != null) return null
        val host = rawHost.removePrefix("[").removeSuffix("]")
        if (user.trim() != user || ':' in user || (user.isEmpty() && pass.isNotEmpty())) return null
        if (listOf(user, pass, label).any { v -> v.any { it.isISOControl() || it == '\uFFFD' } }) return null
        val name = label.trim().ifBlank { "$rawHost:$port" }
        if (name.length > 256) return null
        return ImportedProxy(host, port, type, user, pass, name)
    }
}
