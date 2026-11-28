package ru.arvectum.proxylauncher.storage

import ru.arvectum.proxylauncher.model.ManagedRollbackJournal
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.SavedSubscription
import javax.crypto.SecretKey

/** Dormant review for exact profile state and exact authenticated catalog revision.
 * The revision is opaque encrypted catalog content, never included in the summary.
 */
internal class ManagedOwnershipReview private constructor(
    internal val source: SavedSubscription,
    internal val revision: String,
    internal val selected: String?,
    private val expected: Map<String,Any>,
    private val patch: Map<String,Any?>,
    val kind: Kind,
    val detachedCount: Int,
    val targetProfile: ProxyProfile?,
    val invalidatesRollback: Boolean,
    private val started: Long,
    private val elapsed: () -> Long,
) {
    enum class Kind { REMOVE_SOURCE, MANUAL_EDIT, MANUAL_DELETE }
    private var consumed = false
    override fun toString() = "ManagedOwnershipReview(kind=$kind,count=$detachedCount,invalidatesRollback=$invalidatesRollback)"
    @Synchronized fun cancel() { consumed = true }

    @Synchronized
    fun confirm(transaction: ManagedCrashTransaction, currentRevision: () -> String?,
                allowed: () -> Boolean, acceptRollbackLoss: Boolean,
                removeCatalog: (() -> Boolean)? = null): ManagedCrashTransaction.Outcome {
        if (consumed) return ManagedCrashTransaction.Outcome.STALE
        consumed = true
        if (invalidatesRollback && !acceptRollbackLoss || (kind == Kind.REMOVE_SOURCE) != (removeCatalog != null))
            return ManagedCrashTransaction.Outcome.STALE
        val permitted = { runCatching { allowed() && elapsed()-started in 0 until TTL_MS &&
            currentRevision() == revision }.getOrDefault(false) }
        if (!permitted()) return ManagedCrashTransaction.Outcome.STALE
        return if (removeCatalog == null) transaction.execute(expected,patch,permitted)
        else transaction.executeThen(expected,patch,permitted,removeCatalog)
    }

    companion object {
        const val TTL_MS=300_000L
        fun prepare(source: SavedSubscription, revision: String, raw: Map<String,Any>, selected: String?,
                    elapsed: () -> Long, journalKey: () -> SecretKey,
                    edited: ProxyProfile? = null, encryptedCredential: String? = null, deleteId: String? = null): ManagedOwnershipReview? = runCatching {
            require(revision.isNotEmpty() && revision.length <= 100_000)
            val before = ManagedPreferenceSchema.snapshot(raw,selected)
            require(edited == null || deleteId == null)
            val kind=when { edited!=null -> Kind.MANUAL_EDIT; deleteId!=null -> Kind.MANUAL_DELETE; else -> Kind.REMOVE_SOURCE }
            var patch = when(kind) {
                Kind.MANUAL_EDIT -> ManagedPreferenceSchema.manualEditPatch(raw,before,source.id,edited!!,encryptedCredential)
                Kind.MANUAL_DELETE -> ManagedPreferenceSchema.manualDeletePatch(raw,before,source.id,deleteId!!)
                Kind.REMOVE_SOURCE -> ManagedPreferenceSchema.detachPatch(raw,before,source.id)
            }
            // A source can own no current rows after refresh removed its last row, yet have an undo journal.
            // Authenticate before removal even then; preserve journals belonging to another source when no rows change.
            if (ManagedPreferenceSchema.JOURNAL in raw) {
                val journal=ManagedRollbackJournal.open(raw[ManagedPreferenceSchema.JOURNAL] as String,journalKey())
                if(kind==Kind.REMOVE_SOURCE && journal.belongsTo(source)) patch=patch+(ManagedPreferenceSchema.JOURNAL to null)
            }
            val loss = ManagedPreferenceSchema.JOURNAL in patch && ManagedPreferenceSchema.JOURNAL in raw
            val now = elapsed(); require(now >= 0)
            val frozen = raw.mapValues { (_,v) -> if (v is Set<*>) v.toSet() else v }
            ManagedOwnershipReview(source,revision,selected,frozen,patch.toMap(),
                kind,
                before.rows.count { it.owner == source.id && (kind == Kind.REMOVE_SOURCE || it.profile.id == (edited?.id ?: deleteId)) },edited ?: before.rows.singleOrNull { it.profile.id==deleteId }?.profile,loss,now,elapsed)
        }.getOrNull()
    }
}
