package ru.arvectum.proxylauncher.model

import java.io.InputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CodingErrorAction
import java.util.Locale

/** Pure preview: never writes a profile or makes a network request. */
object ProxyBatchImport {
    const val MAX_BYTES = 256_000
    const val MAX_ENTRIES = 200

    class Preview internal constructor(
        val items: List<ImportedProxy>,
        val skipped: Int,
    ) {
        override fun toString() = "ProxyBatchPreview(count=${items.size}, skipped=$skipped)"
    }

    private data class Key(val type: ProxyType, val host: String, val port: Int, val username: String)

    private fun key(type: ProxyType, host: String, port: Int, username: String?) =
        Key(type, host.removePrefix("[").removeSuffix("]").lowercase(Locale.ROOT), port, username.orEmpty())

    private fun key(item: ImportedProxy) = key(item.type, item.host, item.port, item.username)

    /** Null = invalid/empty/oversized input; never echo the input. */
    fun parse(text: String): List<ImportedProxy>? {
        if (text.length > MAX_BYTES) return null
        val bytes = try {
            Charsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).encode(CharBuffer.wrap(text))
        } catch (_: Exception) { return null }
        if (bytes.remaining() > MAX_BYTES) return null
        val result = mutableListOf<ImportedProxy>()
        val clean = text.trim().removePrefix("\uFEFF").trim()
        for (raw in clean.lineSequence()) {
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith("#")) continue
            if (result.size >= MAX_ENTRIES) return null
            result += ProxyImport.parse(line) ?: return null
        }
        return result.takeIf { it.isNotEmpty() }
    }

    /** Read at most MAX_BYTES+1 bytes, strict UTF-8, close stream at caller. */
    fun readText(stream: InputStream): String? {
        return try {
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val n = stream.read(buffer, 0, minOf(buffer.size, MAX_BYTES + 1 - out.size()))
                if (n < 0) break
                if (n == 0) return null
                out.write(buffer, 0, n)
                if (out.size() > MAX_BYTES) return null
            }
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(out.toByteArray())).toString()
        } catch (_: Exception) { null }
    }

    fun preview(items: List<ImportedProxy>, existing: List<ProxyProfile>): Preview {
        require(items.size in 1..MAX_ENTRIES)
        val seen = existing.mapTo(mutableSetOf()) { key(it.type, it.host, it.port, it.username) }
        val unique = items.filter { seen.add(key(it)) }
        return Preview(unique, items.size - unique.size)
    }
}
