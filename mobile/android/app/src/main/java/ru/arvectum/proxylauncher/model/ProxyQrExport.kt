package ru.arvectum.proxylauncher.model

import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/** User-authorized plaintext disclosure. Never persist or log the returned link. */
object ProxyQrExport {
    const val MAX_PAYLOAD_BYTES = 1800
    private const val HEX = "0123456789ABCDEF"

    private fun encoded(value: String): String = buildString {
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            val n = byte.toInt() and 255
            if (n in 65..90 || n in 97..122 || n in 48..57 || n in listOf(45, 46, 95, 126)) {
                append(n.toChar())
            } else {
                append('%'); append(HEX[n ushr 4]); append(HEX[n and 15])
            }
        }
    }

    fun deepLink(profile: ProxyProfile, password: String?): String? {
        val scheme = when (profile.type) {
            ProxyType.HTTP -> "http"
            ProxyType.HTTPS -> "https"
            ProxyType.SOCKS5 -> "socks5"
            ProxyType.AUTO -> return null
        }
        val host = profile.host.removePrefix("[").removeSuffix("]")
        val username = profile.username.orEmpty()
        val secret = password.orEmpty()
        if (listOf(host, username, secret, profile.name).any { it.length > MAX_PAYLOAD_BYTES }) return null
        if (host.isEmpty() || profile.name.isBlank() || username.isEmpty() && secret.isNotEmpty()) return null
        // Preserve the exact host and all credential fields; validate through the receiver.
        val authority = if (':' in host) "[$host]" else host
        val userInfo = if (username.isNotEmpty()) "${encoded(username)}:${encoded(secret)}@" else ""
        val raw = "$scheme://$userInfo$authority:${profile.port}#${encoded(profile.name)}"
        val link = "arvectum-proxy://import?data=${encoded(raw)}"
        if (link.toByteArray(Charsets.UTF_8).size > MAX_PAYLOAD_BYTES) return null
        val restored = ProxyQrImport.parsePayload(link)?.singleOrNull() ?: return null
        if (restored.host != host || restored.port != profile.port || restored.type != profile.type ||
            restored.username != username || restored.password != secret || restored.name != profile.name) return null
        return link
    }

    fun matrix(profile: ProxyProfile, password: String?): BitMatrix? {
        val link = deepLink(profile, password) ?: return null
        return try {
            QRCodeWriter().encode(link, BarcodeFormat.QR_CODE, 0, 0,
                mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 4))
        } catch (_: Exception) { null }
    }
}
