package ru.arvectum.proxylauncher.model

import java.util.Locale

/** One-shot additive review. Never mutates profiles or exposes credentials in summary. */
internal class SavedSubscriptionReview private constructor(
    private val source: SavedSubscription,
    private val baseline: List<ProxyProfile>,
    val received: Int,
    val preview: ProxyBatchImport.Preview,
    private val elapsed: () -> Long,
    private val started: Long,
) {
    private var consumed = false
    override fun toString() = "SavedSubscriptionReview(redacted)"

    fun cancel() { consumed = true }

    fun confirm(current: SavedSubscription?, existing: List<ProxyProfile>, foreground: Boolean): List<ImportedProxy>? {
        if (consumed) return null
        consumed = true
        val age = elapsed() - started
        if (!foreground || current != source || existing != baseline || age !in 0 until TTL_MS) return null
        return preview.items
    }

    companion object {
        const val TTL_MS = 300_000L
        private const val MAX_EXISTING = 2048
        private data class Endpoint(val type: ProxyType,val host: String,val port: Int,val user: String)
        fun prepare(source: SavedSubscription, items: List<ImportedProxy>, existing: List<ProxyProfile>,
                    elapsed: () -> Long): SavedSubscriptionReview? {
            if (items.size !in 1..ProxyBatchImport.MAX_ENTRIES || existing.size > MAX_EXISTING ||
                existing.map { it.id }.toSet().size != existing.size) return null
            val seen = mutableMapOf<Endpoint,String>()
            for (item in items) {
                val key = Endpoint(item.type,item.host.removePrefix("[").removeSuffix("]").lowercase(Locale.ROOT),
                    item.port,item.username)
                val previous = seen.putIfAbsent(key,item.password)
                if (previous != null && previous != item.password) return null
            }
            val now = elapsed()
            if (now < 0) return null
            return SavedSubscriptionReview(source,existing.toList(),items.size,ProxyBatchImport.preview(items,existing),elapsed,now)
        }
    }
}
