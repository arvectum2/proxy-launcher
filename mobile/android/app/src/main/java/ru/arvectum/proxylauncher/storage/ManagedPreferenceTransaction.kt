package ru.arvectum.proxylauncher.storage

import ru.arvectum.proxylauncher.model.ManagedProfileRow
import ru.arvectum.proxylauncher.model.ManagedProfileState
import ru.arvectum.proxylauncher.model.ManagedSelection
import ru.arvectum.proxylauncher.model.ManagedRollbackJournal
import ru.arvectum.proxylauncher.model.SavedSubscription
import ru.arvectum.proxylauncher.model.ManagedSubscriptionRefresh
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType

/** Storage contract for the profile preferences; no Android or network dependency. */
internal object ManagedPreferenceSchema {
    const val IDS = "profile_ids"
    const val JOURNAL = "managed_rollback_v1"
    private const val ACTIVE = "active_profile_id"
    private const val PRIMARY = "pool_primary_profile_id"
    private const val AUTO = "auto_profile_selection"
    private const val LAST_AUTO = "last_auto_profile_id"
    private const val FAILED = "pool_recently_failed_profile_id"
    private val fields = listOf("name","host","port","type","username","password_ref","subscription_owner")
    fun field(id: String, name: String) = "profile.$id.$name"
    fun secret(id: String) = "secret.$id"

    private fun Map<String,Any>.str(key: String): String? = this[key]?.let { it as String }
    @Suppress("UNCHECKED_CAST")
    fun snapshot(values: Map<String,Any>, selected: String?): ManagedProfileState {
        // No implicit legacy migration or lenient metadata fallback during review.
        val ids = values[IDS]?.let { it as Set<*> } ?: error("Profile index unavailable")
        require(ids.size <= ManagedSubscriptionRefresh.MAX_EXISTING && ids.all { it is String && it.isNotBlank() })
        val rows = (ids as Set<String>).map { id ->
            val profile = ProxyProfile(id,
                values.str(field(id,"name")) ?: error("Profile name missing"),
                values.str(field(id,"host")) ?: error("Profile host missing"),
                values[field(id,"port")] as? Int ?: error("Profile port missing"),
                ProxyType.valueOf(values.str(field(id,"type")) ?: error("Profile type missing")),
                values.str(field(id,"username")),values.str(field(id,"password_ref")))
            val row = ManagedProfileRow(profile,values.str(field(id,"subscription_owner")),values.str(secret(id)))
            require(row.encryptedCredential?.isNotBlank() != false)
            require(profile.passwordRef == null || profile.passwordRef == "android-keystore:$id")
            require(row.owner == null || runCatching { java.util.UUID.fromString(row.owner).toString() }.getOrNull() == row.owner)
            row
        }
        val state = ManagedProfileState(rows,ManagedSelection(
            values.str(ACTIVE),values.str(PRIMARY),values.str(LAST_AUTO),selected,values.str(FAILED),
            values[AUTO]?.let { it as Boolean } ?: false))
        require(ManagedSubscriptionRefresh.validState(state))
        return state
    }

    private fun effectivePrimary(state: ManagedProfileState): String? =
        state.selection.primary?.takeIf { id -> state.rows.any { it.profile.id == id } }
            ?: state.rows.minWithOrNull(compareBy<ManagedProfileRow> { it.profile.name.lowercase(java.util.Locale.ROOT) }
                .thenBy { it.profile.id })?.profile?.id

    /** All changed profile keys, index and journal in one patch; never writes selection or telemetry. */
    fun patch(raw: Map<String,Any>, before: ManagedProfileState, after: ManagedProfileState,
              sourceId: String, journal: String?): Map<String,Any?> =
        buildPatch(raw,before,after,sourceId,journal,false)

    /** The exception for implicit primary is available only through authenticated journal restore. */
    fun rollbackPatch(raw: Map<String,Any>, before: ManagedProfileState, source: SavedSubscription,
                      journalKey: javax.crypto.SecretKey, allowed: Boolean): Map<String,Any?>? {
        if (!allowed || snapshot(raw,before.selection.selected) != before) return null
        val encoded = raw[JOURNAL] as? String ?: return null
        val journal = runCatching { ManagedRollbackJournal.open(encoded,journalKey) }.getOrNull() ?: return null
        val after = journal.restore(source,before,allowed) ?: return null
        val firstImport = before.rows.isNotEmpty() && after.rows.isEmpty() &&
            before.selection.protectedIds.isEmpty() && !before.selection.auto &&
            before.rows.all { it.owner == source.id }
        return buildPatch(raw,before,after,source.id,null,firstImport)
    }

    /** Explicit detach only; preserve every field and ciphertext, even for selected profiles.
     * Invalidate the single global rollback journal, whose exact fingerprint would be stale.
     * Source removal must occur AFTER this patch is durably verified; never the reverse.
     */
    fun detachPatch(raw: Map<String,Any>, before: ManagedProfileState, sourceId: String,
                    profileId: String? = null): Map<String,Any?> {
        require(snapshot(raw,before.selection.selected) == before)
        require(java.util.UUID.fromString(sourceId).toString() == sourceId)
        val owned = before.rows.filter { it.owner == sourceId && (profileId == null || it.profile.id == profileId) }
        if (profileId == null) {
            // An unindexed owner is ambiguous; never silently abandon it during source removal.
            val indexed = owned.map { field(it.profile.id,"subscription_owner") }.toSet()
            require(raw.filter { (k,v) -> k.startsWith("profile.") && k.endsWith(".subscription_owner") && v == sourceId }.keys == indexed)
        } else require(owned.size == 1)
        if (owned.isEmpty()) return emptyMap()
        return owned.associate { field(it.profile.id,"subscription_owner") to null } + (JOURNAL to null)
    }

    /** Manual edit of an owned row detaches in the very same patch, never before/after the edit.
     * Only offline candidate: selection changes and Android UI integration are separate.
     */
    fun manualEditPatch(raw: Map<String,Any>, before: ManagedProfileState, sourceId: String,
                        edited: ProxyProfile, encryptedCredential: String?): Map<String,Any?> {
        val patch = detachPatch(raw,before,sourceId,edited.id).toMutableMap()
        require((edited.passwordRef == null) == (encryptedCredential == null))
        require(edited.passwordRef == null || edited.passwordRef == "android-keystore:${edited.id}")
        require(encryptedCredential?.isNotBlank() != false)
        val values = listOf(edited.name,edited.host,edited.port,edited.type.name,edited.username,edited.passwordRef)
        fields.take(6).zip(values).forEach { (f,v) -> patch[field(edited.id,f)] = v }
        patch[secret(edited.id)] = encryptedCredential
        val target = raw.toMutableMap().apply { patch.forEach { (k,v) -> if(v==null) remove(k) else put(k,v) } }
        val after = snapshot(target,before.selection.selected)
        require(after.rows.single { it.profile.id == edited.id } == ManagedProfileRow(edited,null,encryptedCredential))
        return patch
    }

    private fun buildPatch(raw: Map<String,Any>, before: ManagedProfileState, after: ManagedProfileState,
                           sourceId: String, journal: String?, firstImportRollback: Boolean): Map<String,Any?> {
        require(snapshot(raw,before.selection.selected) == before)
        require(before.selection == after.selection && ManagedSubscriptionRefresh.validState(after))
        val prior = before.rows.associateBy { it.profile.id }
        val next = after.rows.associateBy { it.profile.id }
        val changed = (prior.keys+next.keys).filter { prior[it] != next[it] }
        require(changed.size in 1..400)
        require(changed.none { it in before.protectedIds || (!firstImportRollback && it == effectivePrimary(before)) })
        // Never silently change a non-empty effective fallback primary via alphabetical order.
        require(firstImportRollback || effectivePrimary(before) == null || effectivePrimary(before) == effectivePrimary(after))
        require(changed.all { (prior[it] == null || prior[it]?.owner == sourceId) &&
            (next[it] == null || next[it]?.owner == sourceId) })
        val patch = linkedMapOf<String,Any?>(IDS to next.keys.toSet(), JOURNAL to journal)
        for (id in changed) {
            val row = next[id]
            // A fresh ID must not overwrite orphaned legacy data.
            if (prior[id] == null) require(fields.none { field(id,it) in raw } && secret(id) !in raw)
            val p = row?.profile
            val data = listOf(p?.name,p?.host,p?.port,p?.type?.name,p?.username,p?.passwordRef,row?.owner)
            fields.zip(data).forEach { (f,v) -> patch[field(id,f)] = v }
            patch[secret(id)] = row?.encryptedCredential
        }
        return patch
    }
}

internal interface ManagedPreferenceBackend {
    fun read(): Map<String,Any>
    /** null removes a key; implementation must commit all keys synchronously. */
    fun commit(patch: Map<String,Any?>): Boolean
}

/** Compare, commit, verify readback, and attempt exact affected-key restoration on failure. */
internal class ManagedPreferenceTransaction(private val backend: ManagedPreferenceBackend) {
    enum class Outcome { APPLIED, STALE, RESTORED, RECOVERY_REQUIRED }
    private var recoveryRequired = false

    fun execute(expected: Map<String,Any>, patch: Map<String,Any?>, allowed: () -> Boolean): Outcome {
        if (recoveryRequired) return Outcome.RECOVERY_REQUIRED
        fun gate() = runCatching(allowed).getOrDefault(false)
        if (!gate() || runCatching { backend.read() == expected }.getOrDefault(false).not()) return Outcome.STALE
        val target = expected.toMutableMap().apply {
            patch.forEach { (k,v) -> if (v == null) remove(k) else put(k,v) }
        }
        val committed = runCatching { backend.commit(patch) }.getOrDefault(false)
        val observed = runCatching { backend.read() }.getOrNull()
        if (committed && observed == target && gate()) return Outcome.APPLIED
        // Do not overwrite a third-party edit or guess at an unreadable state.
        if (observed == null || observed.filterKeys { it !in patch } != expected.filterKeys { it !in patch } ||
            patch.keys.any { observed[it] != expected[it] && observed[it] != target[it] } || !gate()) {
            recoveryRequired = true
            return Outcome.RECOVERY_REQUIRED
        }
        val restore = patch.keys.associateWith { expected[it] }
        val restored = runCatching { backend.commit(restore) }.getOrDefault(false)
        if (restored && runCatching { backend.read() == expected }.getOrDefault(false) && gate()) return Outcome.RESTORED
        recoveryRequired = true
        return Outcome.RECOVERY_REQUIRED
    }
}
