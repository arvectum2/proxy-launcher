package ru.arvectum.proxylauncher.model

import java.net.InetAddress
import java.net.URI
import java.io.ByteArrayInputStream
import java.util.Base64
import java.util.Locale

/** Pure subscription policy. Never log a source URL or returned credentials. */
object ProxySubscriptionImport {
    const val MAX_URL_BYTES = 2048
    private val blockedSuffixes = setOf("localhost","local","internal","lan","home","test","invalid","onion","example","arpa")
    private val label = Regex("[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")

    fun source(raw: String): URI? {
        if (raw.length > MAX_URL_BYTES || raw.any { it.isISOControl() } ||
            !Charsets.UTF_8.newEncoder().canEncode(raw) ||
            raw.toByteArray(Charsets.UTF_8).size > MAX_URL_BYTES) return null
        return try {
            val uri = URI(raw.trim())
            val host = uri.host?.lowercase(Locale.ROOT) ?: return null
            val labels = host.split('.')
            if (!uri.scheme.equals("https",true) || uri.rawUserInfo != null || uri.rawFragment != null ||
                uri.port !in listOf(-1,443) ||
                !uri.rawAuthority.equals(host + if (uri.port == 443) ":443" else "", true) || host.length > 253 || labels.size < 2 ||
                labels.any { !label.matches(it) } || labels.last().none { it in 'a'..'z' } ||
                labels.last() in blockedSuffixes) null else uri
        } catch (_: Exception) { null }
    }

    /** Conservative global-unicast policy for the addresses actually supplied to HTTP transport. */
    fun publicAddress(address: InetAddress): Boolean {
        val b = address.address.map { it.toInt() and 255 }
        if (b.size == 4) {
            val (a,c,d) = b
            return !(a == 0 || a == 10 || a == 127 || a >= 224 ||
                a == 100 && c in 64..127 || a == 169 && c == 254 ||
                a == 172 && c in 16..31 || a == 192 && c == 168 ||
                a == 192 && c == 0 && d in listOf(0,2) ||
                a == 192 && c == 88 && d == 99 ||
                a == 198 && c in 18..19 || a == 198 && c == 51 && d == 100 ||
                a == 203 && c == 0 && d == 113)
        }
        if (b.size != 16 || b[0] !in 0x20..0x3f) return false
        // Reject conservative special-purpose, transition and documentation prefixes.
        return !(b[0] == 0x20 && b[1] == 0x01 && (b[2] <= 1 || b[2] == 0x0d && b[3] == 0xb8) ||
            b[0] == 0x20 && b[1] == 0x02 || b[0] == 0x3f && b[1] == 0xff)
    }

    fun decode(bytes: ByteArray): List<ImportedProxy>? {
        if (bytes.isEmpty() || bytes.size > ProxyBatchImport.MAX_BYTES) return null
        val text = ProxyBatchImport.readText(ByteArrayInputStream(bytes)) ?: return null
        if ('\u0000' in text) return null
        ProxyStructuredImport.parseBatch(text)?.let { return it }
        val compact = text.filterNot { it in " \t\r\n" }
        if (compact.isEmpty() || compact.length % 4 != 0 ||
            compact.any { it !in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=" }) return null
        val decoded = try { Base64.getDecoder().decode(compact) } catch (_: IllegalArgumentException) { return null }
        return try {
            // Canonical padded Base64 only; do not silently accept malformed supplier data.
            if (Base64.getEncoder().encodeToString(decoded) != compact) return null
            val payload = ProxyBatchImport.readText(ByteArrayInputStream(decoded)) ?: return null
            if ('\u0000' in payload) null else ProxyStructuredImport.parseBatch(payload)
        } finally { decoded.fill(0) }
    }
}
