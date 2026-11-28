package ru.arvectum.proxylauncher.model

import java.util.Locale
import java.util.UUID

/** Storage snapshot: ciphertext is opaque and never displayed. */
internal class ManagedProfileRow(
    val profile: ProxyProfile,
    val owner: String?,
    val encryptedCredential: String?,
) {
    override fun equals(other: Any?) = other is ManagedProfileRow &&
        profile == other.profile && owner == other.owner && encryptedCredential == other.encryptedCredential
    override fun hashCode() = listOf(profile, owner, encryptedCredential).hashCode()
    override fun toString() = "ManagedProfileRow(redacted)"
}

internal data class ManagedSelection(
    val active: String?, val primary: String?, val lastAuto: String?,
    val selected: String?, val recentlyFailed: String?, val auto: Boolean,
) {
    val protectedIds: Set<String> get() = listOfNotNull(active,primary,lastAuto,selected,recentlyFailed).toSet()
}

internal class ManagedProfileState(rows: List<ManagedProfileRow>, val selection: ManagedSelection) {
    val rows = rows.sortedBy { it.profile.id }
    val protectedIds get() = selection.protectedIds
    override fun equals(other: Any?) = other is ManagedProfileState &&
        rows == other.rows && selection == other.selection
    override fun hashCode() = 31 * rows.hashCode() + selection.hashCode()
    override fun toString() = "ManagedProfileState(count=${rows.size})"
}

/** Pure, single-use review. No ownership inferred from endpoint match. */
internal class ManagedSubscriptionRefresh private constructor(
    private val source: SavedSubscription,
    private val baseline: ManagedProfileState,
    private val changes: List<Change>,
    val summary: Summary,
    private val elapsed: () -> Long,
    private val started: Long,
) {
    enum class Kind { ADD, UPDATE, REMOVE }
    data class Line(val kind: Kind, val type: ProxyType, val host: String, val port: Int)
    data class Summary(val received: Int, val skipped: Int, val unchanged: Int, val lines: List<Line>)
    private class Change(val kind: Kind, val id: String, val item: ImportedProxy?)
    private var consumed = false
    override fun toString() = "ManagedSubscriptionRefresh(redacted)"

    /** Structural projection for review-time primary and orphan checks; no credentials. */
    internal class Projection(val names: Map<String,String>, val changedIds: Set<String>)
    internal fun projection(current: ManagedProfileState): Projection? {
        if (consumed || current != baseline || elapsed()-started !in 0 until TTL_MS) return null
        val names = current.rows.associate { it.profile.id to it.profile.name }.toMutableMap()
        for (change in changes) {
            if (change.kind == Kind.REMOVE) names.remove(change.id)
            else names[change.id] = change.item?.name ?: return null
        }
        return Projection(names.toMap(),changes.map { it.id }.toSet())
    }

    fun cancel() { consumed = true }

    fun confirm(currentSource: SavedSubscription?, current: ManagedProfileState, foregroundDisconnected: Boolean,
                encrypt: (String, ImportedProxy) -> String?): ManagedRefreshTransaction? {
        if (consumed) return null
        consumed = true
        if (!foregroundDisconnected || currentSource != source || current != baseline ||
            elapsed() - started !in 0 until TTL_MS || changes.isEmpty()) return null
        val after = current.rows.associateBy { it.profile.id }.toMutableMap()
        for (change in changes) {
            if (change.id in current.protectedIds) return null
            if (change.kind == Kind.REMOVE) {
                if (after[change.id]?.owner != source.id) return null
                after.remove(change.id)
                continue
            }
            val item = change.item ?: return null
            if (change.kind == Kind.ADD && change.id in after ||
                change.kind == Kind.UPDATE && after[change.id]?.owner != source.id) return null
            val secret = encrypt(change.id,item)
            if ((secret != null) != item.username.isNotEmpty() || secret?.isBlank() == true) return null
            val profile = ProxyProfile(change.id,item.name,item.host,item.port,item.type,
                item.username.takeIf { it.isNotEmpty() },secret?.let { "android-keystore:${change.id}" })
            after[change.id] = ManagedProfileRow(profile,source.id,secret)
        }
        val next = ManagedProfileState(after.values.toList(),current.selection)
        if (!validState(next)) return null
        return ManagedRefreshTransaction(source,current,next,changes.map { it.id }.toSet())
    }

    companion object {
        const val TTL_MS = 300_000L
        const val MAX_EXISTING = 2048
        private data class Endpoint(val type: ProxyType,val host: String,val port: Int,val user: String)
        private fun endpoint(type: ProxyType,host: String,port: Int,user: String?) =
            Endpoint(type,host.removePrefix("[").removeSuffix("]").lowercase(Locale.ROOT),port,user.orEmpty())
        private fun endpoint(p: ProxyProfile) = endpoint(p.type,p.host,p.port,p.username)
        private fun endpoint(p: ImportedProxy) = endpoint(p.type,p.host,p.port,p.username)
        internal fun validState(state: ManagedProfileState): Boolean =
            state.rows.size <= MAX_EXISTING &&
            state.rows.map { it.profile.id }.toSet().size == state.rows.size &&
            state.rows.filter { it.owner != null }.groupingBy { it.owner }.eachCount().values.all { it <= ProxyBatchImport.MAX_ENTRIES } &&
            state.rows.all { row ->
                (row.profile.passwordRef == null) == (row.encryptedCredential == null) &&
                (row.owner == null || row.profile.type != ProxyType.AUTO)
            }

        fun prepare(source: SavedSubscription, incoming: List<ImportedProxy>, current: ManagedProfileState,
                    elapsed: () -> Long, credentialMatches: (ManagedProfileRow, ImportedProxy) -> Boolean,
                    newId: () -> String = { "profile-${UUID.randomUUID()}" }): ManagedSubscriptionRefresh? {
            if (incoming.size !in 1..ProxyBatchImport.MAX_ENTRIES || !validState(current) ||
                runCatching { UUID.fromString(source.id).toString() }.getOrNull() != source.id ||
                source.createdAt < 0 || ProxySubscriptionImport.source("https://${source.host}/")?.host != source.host) return null
            val now = elapsed()
            if (now < 0) return null
            val unique = linkedMapOf<Endpoint,ImportedProxy>()
            var skipped = 0
            for (item in incoming) {
                if (item.type == ProxyType.AUTO || item.username.isEmpty() && item.password.isNotEmpty()) return null
                val key = endpoint(item)
                val previous = unique[key]
                if (previous != null) {
                    if (previous.password != item.password || previous.name != item.name) return null
                    skipped++
                } else unique[key] = item
            }
            val groups = current.rows.groupBy { endpoint(it.profile) }
            val changes = mutableListOf<Change>()
            val lines = mutableListOf<Line>()
            val ids = current.rows.mapTo(mutableSetOf()) { it.profile.id }
            var unchanged = 0
            for ((key,item) in unique) {
                val matching = groups[key].orEmpty()
                val owned = matching.filter { it.owner == source.id }
                if (owned.size > 1 || owned.isNotEmpty() && matching.size != 1) return null
                val row = owned.singleOrNull()
                if (row == null) {
                    if (matching.isNotEmpty()) { skipped++; continue }
                    val id = newId()
                    if (id.isBlank() || id in current.protectedIds || !ids.add(id)) return null
                    changes.add(Change(Kind.ADD,id,item))
                    lines.add(Line(Kind.ADD,item.type,item.host,item.port))
                } else if (row.profile.name == item.name && credentialMatches(row,item)) {
                    unchanged++
                } else {
                    if (row.profile.id in current.protectedIds) return null
                    changes.add(Change(Kind.UPDATE,row.profile.id,item))
                    lines.add(Line(Kind.UPDATE,item.type,item.host,item.port))
                }
            }
            for (row in current.rows.filter { it.owner == source.id && endpoint(it.profile) !in unique }) {
                if (row.profile.id in current.protectedIds) return null
                changes.add(Change(Kind.REMOVE,row.profile.id,null))
                val p = row.profile
                lines.add(Line(Kind.REMOVE,p.type,p.host,p.port))
            }
            val count = current.rows.size + changes.count { it.kind == Kind.ADD } - changes.count { it.kind == Kind.REMOVE }
            if (count !in 0..MAX_EXISTING) return null
            // A response consisting entirely of foreign/manual collisions is not a deletion authorization.
            if (changes.any { it.kind == Kind.REMOVE } && unchanged == 0 && changes.none { it.kind != Kind.REMOVE }) return null
            return ManagedSubscriptionRefresh(source,current,changes.toList(),
                Summary(incoming.size,skipped,unchanged,lines.toList()),elapsed,now)
        }
    }
}

/** Previous configuration, not evidence of connectivity. Inverse is exact-state guarded. */
internal class ManagedRefreshTransaction(
    val source: SavedSubscription,
    val before: ManagedProfileState,
    val after: ManagedProfileState,
    val changedIds: Set<String>,
) {
    override fun toString() = "ManagedRefreshTransaction(changes=${changedIds.size})"

    fun rollback(currentSource: SavedSubscription?, current: ManagedProfileState,
                 foregroundDisconnected: Boolean): ManagedProfileState? {
        if (!foregroundDisconnected || currentSource != source || current != after ||
            changedIds.any { it in current.protectedIds }) return null
        return before
    }
}
