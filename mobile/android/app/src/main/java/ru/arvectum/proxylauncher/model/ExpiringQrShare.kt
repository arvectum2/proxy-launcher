package ru.arvectum.proxylauncher.model

import java.util.UUID

/** A single ephemeral, opaque-token payload. Never persist or log the bytes. */
class ExpiringQrShare(private val now: () -> Long) {
    companion object {
        const val MAX_BYTES = 1_048_576
        const val TTL_MS = 300_000L
    }
    private class Entry(val token: String, val bytes: ByteArray, val expires: Long)
    private var active: Entry? = null

    @Synchronized
    fun issue(png: ByteArray): String? {
        if (png.isEmpty() || png.size > MAX_BYTES) return null
        clear()
        val token = UUID.randomUUID().toString()
        active = Entry(token, png.copyOf(), now() + TTL_MS)
        return token
    }

    @Synchronized
    private fun matching(token: String): Entry? {
        val value = active ?: return null
        if (now() >= value.expires) { clear(); return null }
        return value.takeIf { it.token == token }
    }

    @Synchronized
    fun read(token: String): ByteArray? = matching(token)?.bytes?.copyOf()

    @Synchronized
    fun readInto(token: String, offset: Long, count: Int, target: ByteArray): Int? {
        val bytes = matching(token)?.bytes ?: return null
        if (offset < 0 || count < 0 || count > target.size) return null
        if (offset >= bytes.size) return 0
        val n = minOf(count, bytes.size - offset.toInt())
        bytes.copyInto(target, 0, offset.toInt(), offset.toInt() + n)
        return n
    }

    @Synchronized
    fun size(token: String): Int? = matching(token)?.bytes?.size

    @Synchronized
    fun clear(token: String? = null) {
        if (token != null && active?.token != token) return
        active?.bytes?.fill(0)
        active = null
    }
}
