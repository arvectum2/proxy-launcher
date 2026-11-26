package ru.arvectum.proxylauncher.model

import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.ResultMetadataType
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.multi.qrcode.QRCodeMultiReader
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.URI
import java.net.URLDecoder

/** Pure decoder: no storage or network side effects. */
object ProxyQrImport {
    const val MAX_ENCODED_BYTES = 8 * 1024 * 1024
    const val MAX_SOURCE_PIXELS = 12_000_000L
    const val MAX_DECODED_SIDE = 2048

    fun sampleSize(width: Int, height: Int): Int? {
        if (width <= 0 || height <= 0 || width.toLong() * height > MAX_SOURCE_PIXELS) return null
        var sample = 1
        while ((maxOf(width, height).toLong() + sample - 1) / sample > MAX_DECODED_SIDE) sample *= 2
        return sample
    }

    fun readEncoded(stream: InputStream): ByteArray? = try {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val n = stream.read(buffer, 0, minOf(buffer.size, MAX_ENCODED_BYTES + 1 - out.size()))
            if (n < 0) break
            if (n == 0) throw IllegalArgumentException("Empty read")
            out.write(buffer, 0, n)
            if (out.size() > MAX_ENCODED_BYTES) throw IllegalArgumentException("Image too large")
        }
        out.toByteArray().takeIf { it.isNotEmpty() }
    } catch (_: Exception) { null }

    /** Same ordinary proxy link envelope as iOS sharing, without an exported intent filter. */
    fun parsePayload(raw: String): List<ImportedProxy>? {
        if (raw.length > ProxyImport.MAX_INPUT) return null
        val text = raw.trim()
        if (!text.startsWith("arvectum-proxy:", ignoreCase = true)) return ProxyBatchImport.parse(text)
        return try {
            val uri = URI(text)
            val query = uri.rawQuery ?: return null
            if (!uri.scheme.equals("arvectum-proxy", ignoreCase = true) ||
                !uri.rawAuthority.equals("import", ignoreCase = true) ||
                uri.rawPath != "" || uri.rawFragment != null ||
                !query.startsWith("data=") || '&' in query) return null
            // URI queries are not form-urlencoded: literal '+' must survive.
            val value = URLDecoder.decode(query.substring(5).replace("+", "%2B"), "UTF-8")
            if (value.any { it.isISOControl() || it == '�' }) return null
            ProxyImport.parse(value)?.let { listOf(it) }
        } catch (_: Exception) { null }
    }

    fun decodePixels(width: Int, height: Int, pixels: IntArray): List<ImportedProxy>? {
        if (width !in 1..MAX_DECODED_SIDE || height !in 1..MAX_DECODED_SIDE ||
            pixels.size.toLong() != width.toLong() * height) return null
        return try {
            val image = BinaryBitmap(HybridBinarizer(RGBLuminanceSource(width, height, pixels)))
            val results = QRCodeMultiReader().decodeMultiple(image, mapOf(DecodeHintType.TRY_HARDER to true))
            val result = results.singleOrNull() ?: return null
            // ZXing's structured-append merge produces an empty point list.
            if (result.resultPoints.isNullOrEmpty() ||
                result.resultMetadata?.containsKey(ResultMetadataType.STRUCTURED_APPEND_SEQUENCE) == true) return null
            parsePayload(result.text)
        } catch (_: Exception) { null }
    }
}
