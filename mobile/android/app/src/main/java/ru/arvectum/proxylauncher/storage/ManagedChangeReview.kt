package ru.arvectum.proxylauncher.storage

import ru.arvectum.proxylauncher.model.ManagedProfileRow
import ru.arvectum.proxylauncher.model.ManagedProfileState
import ru.arvectum.proxylauncher.model.ManagedRollbackJournal
import ru.arvectum.proxylauncher.model.ManagedSubscriptionRefresh
import ru.arvectum.proxylauncher.model.SavedSubscription
import javax.crypto.SecretKey

/** One-shot, exact reviewed state; no catalog credentials or ciphertext in display fields. */
internal class ManagedChangeReview private constructor(
    internal val source: SavedSubscription,
    internal val selected: String?,
    private val revision: String,
    private val expected: Map<String,Any>,
    val kind: Kind,
    val lines: List<ManagedSubscriptionRefresh.Line>,
    val replacesRollback: Boolean,
    private val started: Long,
    private val elapsed: () -> Long,
    private val makePatch: () -> Map<String,Any?>?,
    private val cancelPlan: () -> Unit,
) {
    enum class Kind { REFRESH, ROLLBACK }
    private var consumed = false
    override fun toString() = "ManagedChangeReview(kind=$kind,count=${lines.size})"
    @Synchronized fun cancel() { consumed = true; cancelPlan() }

    @Synchronized
    fun confirm(transaction: ManagedCrashTransaction, currentRaw: () -> Map<String,Any>,
                currentRevision: () -> String?, currentSelection: () -> String?, allowed: () -> Boolean,
                acceptRollbackReplacement: Boolean): ManagedCrashTransaction.Outcome {
        if (consumed) return ManagedCrashTransaction.Outcome.STALE
        consumed = true
        val permitted = { runCatching { allowed() && currentSelection() == selected &&
            elapsed()-started in 0 until TTL_MS && currentRevision() == revision }.getOrDefault(false) }
        try {
            if (replacesRollback && !acceptRollbackReplacement || !permitted() ||
                !runCatching { currentRaw() == expected }.getOrDefault(false)) return ManagedCrashTransaction.Outcome.STALE
            return transaction.executePrepared(expected,permitted,makePatch)
        } finally { cancelPlan() }
    }

    companion object {
        const val TTL_MS = 300_000L
        private fun freeze(raw: Map<String,Any>) = raw.mapValues { (_,v) -> if (v is Set<*>) v.toSet() else v }
        fun refresh(source: SavedSubscription, revision: String, raw: Map<String,Any>, selected: String?,
                    plan: ManagedSubscriptionRefresh, elapsed: () -> Long, authenticateJournal: () -> Unit,
                    build: (ManagedSubscriptionRefresh,Map<String,Any>) -> Map<String,Any?>?): ManagedChangeReview? = runCatching {
            require(revision.isNotEmpty() && revision.length<=100_000 && plan.summary.lines.isNotEmpty())
            val baseline=ManagedPreferenceSchema.snapshot(raw,selected)
            val projection=plan.projection(baseline) ?: return null
            if (!ManagedPreferenceSchema.validateRefreshPreview(raw,baseline,projection)) { plan.cancel(); return null }
            val previous = ManagedPreferenceSchema.JOURNAL in raw
            if (previous) authenticateJournal()
            val now = elapsed(); require(now>=0)
            val frozen=freeze(raw)
            ManagedChangeReview(source,selected,revision,frozen,Kind.REFRESH,plan.summary.lines.toList(),previous,now,elapsed,
                { build(plan,frozen) },plan::cancel)
        }.getOrNull()

        fun rollback(source: SavedSubscription, revision: String, raw: Map<String,Any>, selected: String?,
                     elapsed: () -> Long, journalKey: SecretKey,
                     verifyCredential: (ManagedProfileRow) -> Unit): ManagedChangeReview? = runCatching {
            require(revision.isNotEmpty() && revision.length<=100_000)
            val before=ManagedPreferenceSchema.snapshot(raw,selected)
            val encoded=raw[ManagedPreferenceSchema.JOURNAL] as String
            val journal=ManagedRollbackJournal.open(encoded,journalKey)
            val after=journal.restore(source,before,true) ?: return null
            val patch=ManagedPreferenceSchema.rollbackPatch(raw,before,source,journalKey,true) ?: return null
            after.rows.forEach(verifyCredential)
            val lines=diff(before,after)
            require(lines.isNotEmpty())
            val now=elapsed();require(now>=0)
            ManagedChangeReview(source,selected,revision,freeze(raw),Kind.ROLLBACK,lines,false,now,elapsed,
                { after.rows.forEach(verifyCredential);patch },{})
        }.getOrNull()

        private fun diff(before: ManagedProfileState,after: ManagedProfileState): List<ManagedSubscriptionRefresh.Line> {
            val old=before.rows.associateBy { it.profile.id };val next=after.rows.associateBy { it.profile.id }
            return (old.keys+next.keys).sorted().mapNotNull { id ->
                val a=old[id];val b=next[id];if(a==b) return@mapNotNull null
                val p=(b?:a!!).profile
                val kind=when { a==null -> ManagedSubscriptionRefresh.Kind.ADD; b==null -> ManagedSubscriptionRefresh.Kind.REMOVE; else -> ManagedSubscriptionRefresh.Kind.UPDATE }
                ManagedSubscriptionRefresh.Line(kind,p.type,p.host,p.port)
            }
        }
    }
}
