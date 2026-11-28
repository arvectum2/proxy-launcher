package ru.arvectum.proxylauncher.storage

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.util.Locale
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import ru.arvectum.proxylauncher.model.PrimaryRestorePolicy
import ru.arvectum.proxylauncher.model.ManagedProfileState
import ru.arvectum.proxylauncher.model.ManagedRollbackJournal
import ru.arvectum.proxylauncher.model.ManagedSubscriptionRefresh
import ru.arvectum.proxylauncher.model.SavedSubscription
import ru.arvectum.proxylauncher.model.ImportedProxy
import ru.arvectum.proxylauncher.model.ProxyBatchImport
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType
import ru.arvectum.proxylauncher.routing.ApplicationExclusionPolicy
import ru.arvectum.proxylauncher.routing.SiteExclusionPolicy

data class ResolvedProxyProfile(
    val profile: ProxyProfile,
    val password: String?,
)

class SecureProfileStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val appContext = context.applicationContext

    // Managed mutation is deliberately not reachable from UI until the process and device gate.
    private val managedBackend = object : ManagedPreferenceBackend {
        override fun read(): Map<String,Any> = prefs.all.mapValues { (_, value) ->
            when (value) {
                is Set<*> -> value.toSet()
                null -> error("Unexpected null preference")
                else -> value
            }
        }

        override fun commit(patch: Map<String,Any?>): Boolean {
            val editor = prefs.edit()
            for ((key,value) in patch) when (value) {
                null -> editor.remove(key)
                is String -> editor.putString(key,value)
                is Int -> editor.putInt(key,value)
                is Set<*> -> {
                    require(value.all { it is String })
                    editor.putStringSet(key,value.map { it as String }.toSet())
                }
                else -> error("Unsupported managed preference value")
            }
            return editor.commit()
        }
    }

    private val managedGate by lazy {
        managedProfileGate(appContext)
    }
    private val managedDisk by lazy {
        ManagedPreferenceDiskVerifier(appContext.dataDir.toPath().resolve("shared_prefs").resolve("$PREFS_NAME.xml"))
    }
    private val managedTransaction by lazy {
        ManagedCrashTransaction(managedGate,managedBackend,{ managedEvidenceKey(true) },managedDisk::matches)
    }

    private fun <T> ordinaryWrite(block: () -> T): T =
        ManagedOrdinaryWriteGuard.write(managedGate,{ managedRecoveryRequired },block)

    private fun ordinaryWriteIfAvailable(block: () -> Unit) =
        ManagedOrdinaryWriteGuard.ifAvailable(managedGate,{ managedRecoveryRequired },block)

    private fun managedEvidenceKey(allowCreate: Boolean): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(MANAGED_EVIDENCE_ALIAS,null) as? SecretKey)?.let { return it }
        check(allowCreate) { "Managed evidence key unavailable" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(MANAGED_EVIDENCE_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    /** Read-only classification, never clears an abandoned marker or restores data. */
    @Synchronized
    internal fun inspectManagedCrash(allowed: () -> Boolean): ManagedRecoveryEvidence.State {
        return synchronized(ManagedOrdinaryWriteGuard.monitor) {
            if (!managedProcessIdle() || !allowed()) return ManagedRecoveryEvidence.State.UNKNOWN
            return managedGate.inspectPending { payload ->
                if (!managedProcessIdle() || !allowed()) ManagedRecoveryEvidence.State.UNKNOWN
                else ManagedRecoveryEvidence.open(payload,managedEvidenceKey(false)).classify(managedDisk.readVerified())
            }
        }
    }

    // UI is not wired until the VPN process participates in the same lock.
    private fun verifiedManagedDiskState(): Map<String,Any> {
        val disk = managedDisk.readVerified()
        check(managedBackend.read() == disk) { "Cached profiles differ from disk" }
        return disk
    }

    @Synchronized
    internal fun prepareManagedRecoveryReview(allowed: () -> Boolean): ManagedRecoveryReview? =
        synchronized(ManagedOrdinaryWriteGuard.monitor) {
            ManagedRecoveryReview.prepare(managedGate,{ managedEvidenceKey(false) },::verifiedManagedDiskState,
                android.os.SystemClock::elapsedRealtime) { managedProcessIdle() && allowed() }
        }

    @Synchronized
    internal fun acknowledgeManagedRecovery(review: ManagedRecoveryReview,allowed: () -> Boolean): Boolean {
        return synchronized(ManagedOrdinaryWriteGuard.monitor) {
            val success=review.confirm(managedGate,{ managedEvidenceKey(false) },::verifiedManagedDiskState) {
                managedProcessIdle() && allowed()
            }
            if (success) managedRecoveryRequired=false
            return success
        }
    }

    /** Conservative preliminary process guard, not a cross-process lock. No caller in production yet. */
    private fun managedProcessIdle(): Boolean {
        if (android.os.Looper.myLooper() != android.os.Looper.getMainLooper()) return false
        val manager = appContext.getSystemService(android.app.ActivityManager::class.java) ?: return false
        val processes = manager.runningAppProcesses ?: return false
        val own = processes.filter { it.uid == android.os.Process.myUid() }
        return own.any { it.pid == android.os.Process.myPid() && it.processName == appContext.packageName } &&
            own.none { it.processName == appContext.packageName + ":vpn" }
    }

    private fun managedJournalKey(allowCreate: Boolean): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(MANAGED_JOURNAL_ALIAS,null) as? SecretKey)?.let { return it }
        check(allowCreate) { "Managed journal key unavailable" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(MANAGED_JOURNAL_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    private fun existingCredentialKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return ks.getKey(KEY_ALIAS,null) as? SecretKey ?: error("Profile key unavailable")
    }

    @Synchronized
    internal fun prepareManagedRefresh(catalog: SecureSubscriptionStore, fetched: SecureSubscriptionStore.ManagedFetchInput,
                                       items: List<ImportedProxy>, selected: String?,
                                       allowed: () -> Boolean): ManagedChangeReview? {
        return synchronized(ManagedOrdinaryWriteGuard.monitor) {
            if (managedRecoveryRequired || !managedProcessIdle() || !allowed()) return null
            runCatching {
                catalog.withManagedCatalog {
                    val lease = managedGate.acquire().lease ?: return@withManagedCatalog null
                    lease.use {
                        val raw = verifiedManagedDiskState()
                        val source = fetched.source
                        val revision = catalog.managedRevision(source) ?: return@use null
                        if (revision != fetched.revision || !managedProcessIdle() || !allowed()) return@use null
                        val before = ManagedPreferenceSchema.snapshot(raw,selected)
                        val plan = ManagedSubscriptionRefresh.prepare(source,items,before,android.os.SystemClock::elapsedRealtime,
                            { row,item ->
                                val secret = row.encryptedCredential
                                if (secret == null) item.username.isEmpty() && item.password.isEmpty()
                                else decrypt(secret,existingCredentialKey()) == item.password
                            }) ?: return@use null
                        ManagedChangeReview.refresh(source,revision,raw,selected,plan,android.os.SystemClock::elapsedRealtime,
                            { ManagedRollbackJournal.open(raw[ManagedPreferenceSchema.JOURNAL] as String,managedJournalKey(false)) },
                            { reviewed,expected -> buildManagedRefreshPatch(reviewed,expected,source,selected) })
                    }
                }
            }.getOrNull()
        }
    }

    private fun buildManagedRefreshPatch(review: ManagedSubscriptionRefresh, raw: Map<String,Any>,
                                         source: SavedSubscription, selected: String?): Map<String,Any?>? {
        val before = ManagedPreferenceSchema.snapshot(raw,selected)
        val key by lazy {
            if (before.rows.any { it.encryptedCredential != null }) existingCredentialKey() else getOrCreateKey()
        }
        val txn = review.confirm(source,before,true) { _,item ->
            if (item.username.isEmpty()) null else {
                val chars = item.password.toCharArray()
                try { encrypt(chars,key) } finally { chars.fill(Char.MIN_VALUE) }
            }
        } ?: return null
        val previousJournal = raw[ManagedPreferenceSchema.JOURNAL]
        val journalKey = managedJournalKey(previousJournal == null)
        if (previousJournal != null) ManagedRollbackJournal.open(previousJournal as String,journalKey)
        for (row in before.rows) if (row.profile.id in txn.changedIds && row.encryptedCredential != null)
            decrypt(row.encryptedCredential,existingCredentialKey())
        val journal = ManagedRollbackJournal.from(txn).seal(journalKey)
        return ManagedPreferenceSchema.patch(raw,before,txn.after,txn.source.id,journal)
    }

    @Synchronized
    internal fun prepareManagedRollback(catalog: SecureSubscriptionStore, source: SavedSubscription,
                                        selected: String?, allowed: () -> Boolean): ManagedChangeReview? {
        return synchronized(ManagedOrdinaryWriteGuard.monitor) {
            if (managedRecoveryRequired || !managedProcessIdle() || !allowed()) return null
            runCatching {
                catalog.withManagedCatalog {
                    val lease = managedGate.acquire().lease ?: return@withManagedCatalog null
                    lease.use {
                        val raw=verifiedManagedDiskState()
                        val revision=catalog.managedRevision(source) ?: return@use null
                        if (!managedProcessIdle() || !allowed()) return@use null
                        ManagedChangeReview.rollback(source,revision,raw,selected,android.os.SystemClock::elapsedRealtime,
                            managedJournalKey(false)) { row ->
                            row.encryptedCredential?.let { decrypt(it,existingCredentialKey()) }
                        }
                    }
                }
            }.getOrNull()
        }
    }

    @Synchronized
    internal fun confirmManagedChange(review: ManagedChangeReview, catalog: SecureSubscriptionStore,
                                      selected: () -> String?, allowed: () -> Boolean,
                                      acceptRollbackReplacement: Boolean): ManagedCrashTransaction.Outcome {
        return synchronized(ManagedOrdinaryWriteGuard.monitor) {
            val permitted = { !managedRecoveryRequired && managedProcessIdle() && allowed() }
            val outcome = catalog.withManagedCatalog {
                review.confirm(managedTransaction,managedBackend::read,{ catalog.managedRevision(review.source) },
                    selected,permitted,acceptRollbackReplacement)
            }
            if (outcome == ManagedCrashTransaction.Outcome.RECOVERY_REQUIRED) managedRecoveryRequired = true
            outcome
        }
    }

    /** Dormant adapter: caller must cancel on lifecycle/selection change and show rollback-loss warning. */
    @Synchronized
    internal fun prepareManagedOwnership(catalog: SecureSubscriptionStore, source: SavedSubscription,
                                         selected: String?, allowed: () -> Boolean,
                                         edited: ProxyProfile? = null, encryptedCredential: String? = null): ManagedOwnershipReview? {
        return synchronized(ManagedOrdinaryWriteGuard.monitor) {
            if (managedRecoveryRequired || !managedProcessIdle() || !allowed()) return null
            return runCatching {
                catalog.withManagedCatalog {
                    val lease = managedGate.acquire().lease ?: return@withManagedCatalog null
                    lease.use {
                        val raw = verifiedManagedDiskState()
                        val revision = catalog.managedRevision(source) ?: return@use null
                        if (!managedProcessIdle() || !allowed()) return@use null
                        if (edited != null && encryptedCredential != null) decrypt(encryptedCredential,existingCredentialKey())
                        ManagedOwnershipReview.prepare(source,revision,raw,selected,android.os.SystemClock::elapsedRealtime,
                            { managedJournalKey(false) },edited,encryptedCredential)
                    }
                }
            }.getOrNull()
        }
    }

    @Synchronized
    internal fun confirmManagedOwnership(review: ManagedOwnershipReview, catalog: SecureSubscriptionStore,
                                         selected: () -> String?, allowed: () -> Boolean,
                                         acceptRollbackLoss: Boolean): ManagedCrashTransaction.Outcome {
        return synchronized(ManagedOrdinaryWriteGuard.monitor) {
            val permitted = { !managedRecoveryRequired && managedProcessIdle() && allowed() && selected() == review.selected }
            val outcome = catalog.withManagedCatalog {
                review.confirm(managedTransaction,{ catalog.managedRevision(review.source) },permitted,acceptRollbackLoss,
                    if (review.kind == ManagedOwnershipReview.Kind.REMOVE_SOURCE)
                        ({ catalog.removeManagedExact(review.source,review.revision) }) else null)
            }
            if (outcome == ManagedCrashTransaction.Outcome.RECOVERY_REQUIRED) managedRecoveryRequired = true
            return outcome
        }
    }

    init {
        ordinaryWriteIfAvailable {
            val obsolete = listOf(LEGACY_GATEWAY_LOCATION_ID,LEGACY_GATEWAY_LOCATION_LABEL,
                LEGACY_GATEWAY_RECOVERY_WINDOW,LEGACY_GATEWAY_RECOVERY_ATTEMPT)
            if (obsolete.any(prefs::contains)) {
                val editor = prefs.edit()
                obsolete.forEach { editor.remove(it) }
                check(editor.commit()) { "Failed to clear obsolete profile state" }
            }
        }
    }

    /**
     * Commit synchronously: the VPN service runs in a separate process so the active
     * profile must be on disk before Android starts that process.
     */
    fun saveActive(profile: ProxyProfile, password: CharArray?) {
        saveProfile(profile, password, makeActive = true)
    }

    fun saveProfile(profile: ProxyProfile, password: CharArray?, makeActive: Boolean = true) {
        ordinaryWrite {
            check(!prefs.contains(profileKey(profile.id,"subscription_owner"))) { "Managed profile requires review" }
            ensureLegacyProfileIndexed()

            val passwordRef = if (password != null) {
                val ok = prefs.edit().putString(secretKey(profile.id), encrypt(password)).commit()
                check(ok) { "Failed to persist encrypted credential" }
                "android-keystore:${profile.id}"
            } else {
                val ok = prefs.edit().remove(secretKey(profile.id)).commit()
                check(ok) { "Failed to clear encrypted credential" }
                null
            }

            val ids = profileIds().toMutableSet().apply { add(profile.id) }
            val editor = prefs.edit()
                .putStringSet(KEY_PROFILE_IDS, ids)
                .putString(profileKey(profile.id, "name"), profile.name)
                .putString(profileKey(profile.id, "host"), profile.host)
                .putInt(profileKey(profile.id, "port"), profile.port)
                .putString(profileKey(profile.id, "type"), profile.type.name)
                .putString(profileKey(profile.id, "username"), profile.username)
                .putString(profileKey(profile.id, "password_ref"), passwordRef)
            if (makeActive) {
                editor.putString(KEY_ACTIVE_ID, profile.id)
                    .putBoolean(KEY_AUTO_SELECTION, false)
            }
            check(editor.commit()) { "Failed to persist proxy profile" }
        }
    }

    /** UI-only disconnected import. Existing profiles, selection and priority are untouched. */
    @Synchronized
    fun appendImportedProfiles(items: List<ImportedProxy>): Int {
        return ordinaryWrite {
            require(items.size in 1..ProxyBatchImport.MAX_ENTRIES)
            ensureLegacyProfileIndexed()
            check(ProxyBatchImport.preview(items, listProfiles()).skipped == 0) {
                "Import preview is stale"
            }
            val originalIds = profileIds()
            val ids = originalIds.toMutableSet()
            val key by lazy { getOrCreateKey() }
            val staged = items.map { item ->
                val id = "profile-${UUID.randomUUID()}"
                check(ids.add(id)) { "Profile identity collision" }
                val secret = if (item.username.isNotEmpty()) {
                    val chars = item.password.toCharArray()
                    try { encrypt(chars, key) } finally { chars.fill(Char.MIN_VALUE) }
                } else null
                Triple(id, item, secret)
            }
            val editor = prefs.edit().putStringSet(KEY_PROFILE_IDS, ids)
            for ((id, item, secret) in staged) {
                editor.putString(profileKey(id, "name"), item.name)
                    .putString(profileKey(id, "host"), item.host)
                    .putInt(profileKey(id, "port"), item.port)
                    .putString(profileKey(id, "type"), item.type.name)
                    .putString(profileKey(id, "username"), item.username.takeIf { it.isNotEmpty() })
                    .putString(profileKey(id, "password_ref"), secret?.let { "android-keystore:$id" })
                if (secret != null) editor.putString(secretKey(id), secret)
            }
            if (!editor.commit()) {
                // SharedPreferences may update memory even on disk failure. Attempt bounded rollback.
                val rollback = prefs.edit().putStringSet(KEY_PROFILE_IDS, originalIds)
                for ((id, _, _) in staged) {
                    for (field in listOf("name", "host", "port", "type", "username", "password_ref")) {
                        rollback.remove(profileKey(id, field))
                    }
                    rollback.remove(secretKey(id))
                }
                check(rollback.commit()) { "Import storage recovery failed" }
                error("Import storage failed")
            }
            return@ordinaryWrite staged.size
        }
    }

    fun listProfiles(): List<ProxyProfile> {
        ensureLegacyProfileIndexed()
        return profileIds()
            .mapNotNull(::loadProfileMetadata)
            .sortedWith(compareBy<ProxyProfile> { it.name.lowercase(Locale.ROOT) }.thenBy { it.id })
    }

    fun getActiveProfileId(): String? {
        ensureLegacyProfileIndexed()
        return prefs.getString(KEY_ACTIVE_ID, null)
    }

    fun isAutoProfileSelection(): Boolean {
        ensureLegacyProfileIndexed()
        return prefs.getBoolean(KEY_AUTO_SELECTION, false)
    }

    fun setAutoProfileSelection(enabled: Boolean) {
        ordinaryWrite {
            ensureLegacyProfileIndexed()
            val editor = prefs.edit().putBoolean(KEY_AUTO_SELECTION, enabled)
            check(editor.commit()) { "Failed to persist Auto proxy selection" }
        }
    }

    fun getLastAutoProfileId(): String? {
        ensureLegacyProfileIndexed()
        return prefs.getString(KEY_LAST_AUTO_ID, null)
    }

    fun setLastAutoProfileId(id: String?) {
        ordinaryWrite {
            ensureLegacyProfileIndexed()
            val editor = prefs.edit()
            if (id == null) {
                editor.remove(KEY_LAST_AUTO_ID)
            } else {
                require(loadProfileMetadata(id) != null) { "Unknown proxy profile" }
                editor.putString(KEY_LAST_AUTO_ID, id)
            }
            check(editor.commit()) { "Failed to persist last Auto proxy" }
        }
    }

    fun setActiveProfile(id: String) {
        ordinaryWrite {
            ensureLegacyProfileIndexed()
            require(loadProfileMetadata(id) != null) { "Unknown proxy profile" }
            check(
                prefs.edit()
                    .putString(KEY_ACTIVE_ID, id)
                    .putBoolean(KEY_AUTO_SELECTION, false)
                    .commit(),
            ) {
                "Failed to persist active proxy profile"
            }
        }
    }

    fun loadProfile(id: String): ResolvedProxyProfile? {
        ensureLegacyProfileIndexed()
        val profile = loadProfileMetadata(id) ?: return null
        val password = if (profile.passwordRef != null) {
            val encrypted = prefs.getString(secretKey(id), null)
                ?: error("Encrypted password is missing")
            decrypt(encrypted)
        } else {
            null
        }
        return ResolvedProxyProfile(profile, password)
    }

    fun loadActive(): ResolvedProxyProfile? {
        val id = getActiveProfileId() ?: return null
        return loadProfile(id)
    }

    fun deleteProfile(id: String) {
        ordinaryWrite {
            check(!prefs.contains(profileKey(id,"subscription_owner"))) { "Managed profile requires review" }
            ensureLegacyProfileIndexed()
            if (loadProfileMetadata(id) == null) return@ordinaryWrite

            val remainingIds = profileIds().toMutableSet().apply { remove(id) }
            val nextActiveId = if (prefs.getString(KEY_ACTIVE_ID, null) == id) {
                remainingIds
                    .mapNotNull(::loadProfileMetadata)
                    .sortedWith(compareBy<ProxyProfile> { it.name.lowercase(Locale.ROOT) }.thenBy { it.id })
                    .firstOrNull()
                    ?.id
            } else {
                prefs.getString(KEY_ACTIVE_ID, null)
            }

            val editor = prefs.edit()
                .putStringSet(KEY_PROFILE_IDS, remainingIds)
                .remove(secretKey(id))
                .remove(profileKey(id, "name"))
                .remove(profileKey(id, "host"))
                .remove(profileKey(id, "port"))
                .remove(profileKey(id, "type"))
                .remove(profileKey(id, "username"))
                .remove(profileKey(id, "password_ref"))

            if (nextActiveId == null) {
                editor.remove(KEY_ACTIVE_ID)
            } else {
                editor.putString(KEY_ACTIVE_ID, nextActiveId)
            }
            if (prefs.getString(KEY_LAST_AUTO_ID, null) == id) {
                editor.remove(KEY_LAST_AUTO_ID)
            }
            if (prefs.getString(KEY_PRIMARY_ID, null) == id) {
                val nextPrimary = remainingIds
                    .mapNotNull(::loadProfileMetadata)
                    .sortedWith(compareBy<ProxyProfile> { it.name.lowercase(Locale.ROOT) }.thenBy { it.id })
                    .firstOrNull()
                    ?.id
                if (nextPrimary == null) editor.remove(KEY_PRIMARY_ID)
                else editor.putString(KEY_PRIMARY_ID, nextPrimary)
            }
            if (prefs.getString(KEY_RECENTLY_FAILED_ID, null) == id) {
                editor.remove(KEY_RECENTLY_FAILED_ID).remove(KEY_RECENTLY_FAILED_AT)
            }
            check(editor.commit()) { "Failed to delete proxy profile" }
        }
    }

    fun getPrimaryProfileId(): String? {
        ensureLegacyProfileIndexed()
        val stored = prefs.getString(KEY_PRIMARY_ID, null)
        if (stored != null && loadProfileMetadata(stored) != null) return stored
        return listProfiles().firstOrNull()?.id
    }

    fun setPrimaryProfileId(id: String) {
        ordinaryWrite {
            ensureLegacyProfileIndexed()
            require(loadProfileMetadata(id) != null) { "Unknown proxy profile" }
            check(prefs.edit().putString(KEY_PRIMARY_ID, id).commit()) {
                "Failed to persist primary proxy"
            }
        }
    }

    fun getRestorePolicy(): PrimaryRestorePolicy = runCatching {
        PrimaryRestorePolicy.valueOf(
            prefs.getString(KEY_RESTORE_POLICY, PrimaryRestorePolicy.STAY_ON_CURRENT.name)!!,
        )
    }.getOrDefault(PrimaryRestorePolicy.STAY_ON_CURRENT)

    fun setRestorePolicy(policy: PrimaryRestorePolicy) {
        ordinaryWrite {
            check(prefs.edit().putString(KEY_RESTORE_POLICY, policy.name).commit()) {
                "Failed to persist primary restore policy"
            }
        }
    }

    fun markRecentlyFailedProfile(id: String, atMs: Long = System.currentTimeMillis()) {
        ordinaryWrite {
            check(
                prefs.edit()
                    .putString(KEY_RECENTLY_FAILED_ID, id)
                    .putLong(KEY_RECENTLY_FAILED_AT, atMs)
                    .commit(),
            ) { "Failed to persist failed proxy state" }
        }
    }

    fun getRecentlyFailedProfileId(): String? = prefs.getString(KEY_RECENTLY_FAILED_ID, null)

    fun getRecentlyFailedAtMs(): Long = prefs.getLong(KEY_RECENTLY_FAILED_AT, 0L)

    fun clearRecentlyFailedProfile() {
        ordinaryWrite {
            prefs.edit().remove(KEY_RECENTLY_FAILED_ID).remove(KEY_RECENTLY_FAILED_AT).commit()
        }
    }

    fun setLastFailoverAtMs(value: Long) {
        ordinaryWrite {
            prefs.edit().putLong(KEY_LAST_FAILOVER_AT, value).commit()
        }
    }

    fun getLastFailoverAtMs(): Long = prefs.getLong(KEY_LAST_FAILOVER_AT, 0L)

    fun markVpnProcessRestartPending() {
        ordinaryWrite {
            check(prefs.edit().putBoolean(KEY_VPN_PROCESS_RESTART_PENDING, true).commit()) {
                "Failed to persist VPN restart handoff state"
            }
        }
    }

    @Synchronized
    fun consumeVpnProcessRestartPending(): Boolean {
        return ordinaryWrite {
            val pending = prefs.getBoolean(KEY_VPN_PROCESS_RESTART_PENDING, false)
            if (pending) {
                prefs.edit().putBoolean(KEY_VPN_PROCESS_RESTART_PENDING, false).commit()
            }
            return@ordinaryWrite pending
        }
    }

    fun clearVpnProcessRestartPending() {
        ordinaryWrite {
            prefs.edit().putBoolean(KEY_VPN_PROCESS_RESTART_PENDING, false).commit()
        }
    }

    fun getSiteExclusions(): List<String> =
        prefs.getStringSet(KEY_SITE_EXCLUSIONS, emptySet())
            ?.toList()
            .orEmpty()
            .sorted()

    fun setSiteExclusions(entries: Collection<String>) {
        ordinaryWrite {
            val normalized = SiteExclusionPolicy.normalizeAll(entries)
            check(prefs.edit().putStringSet(KEY_SITE_EXCLUSIONS, normalized.toSet()).commit()) {
                "Failed to persist site exclusions"
            }
        }
    }

    fun getAppExclusions(): List<String> =
        prefs.getStringSet(KEY_APP_EXCLUSIONS, emptySet())
            ?.toList()
            .orEmpty()
            .sorted()

    fun setAppExclusions(packageIds: Collection<String>) {
        ordinaryWrite {
            val normalized = ApplicationExclusionPolicy.normalizeAll(packageIds)
            check(prefs.edit().putStringSet(KEY_APP_EXCLUSIONS, normalized.toSet()).commit()) {
                "Failed to persist application exclusions"
            }
        }
    }

    private fun legacyProfileIds(): Set<String> {
        val activeId = prefs.getString(KEY_ACTIVE_ID, null)
        return if (activeId != null && prefs.getString(profileKey(activeId,"host"),null) != null)
            setOf(activeId) else emptySet()
    }

    private fun ensureLegacyProfileIndexed() {
        if (prefs.contains(KEY_PROFILE_IDS)) return
        ordinaryWriteIfAvailable {
            if (!prefs.contains(KEY_PROFILE_IDS)) check(prefs.edit().putStringSet(KEY_PROFILE_IDS,legacyProfileIds()).commit()) {
                "Failed to initialize proxy profile index"
            }
        }
    }

    private fun profileIds(): Set<String> =
        if (prefs.contains(KEY_PROFILE_IDS)) prefs.getStringSet(KEY_PROFILE_IDS,emptySet())?.toSet().orEmpty()
        else legacyProfileIds()

    private fun loadProfileMetadata(id: String): ProxyProfile? {
        val host = prefs.getString(profileKey(id, "host"), null) ?: return null
        val port = prefs.getInt(profileKey(id, "port"), -1)
        if (port !in 1..65535) return null
        val type = runCatching {
            ProxyType.valueOf(prefs.getString(profileKey(id, "type"), ProxyType.AUTO.name)!!)
        }.getOrDefault(ProxyType.AUTO)
        return ProxyProfile(
            id = id,
            name = prefs.getString(profileKey(id, "name"), "$host:$port") ?: "$host:$port",
            host = host,
            port = port,
            type = type,
            username = prefs.getString(profileKey(id, "username"), null),
            passwordRef = prefs.getString(profileKey(id, "password_ref"), null),
        )
    }

    private fun encrypt(value: CharArray, key: SecretKey = getOrCreateKey()): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val plaintext = String(value).toByteArray(Charsets.UTF_8)
        return try {
            val ciphertext = cipher.doFinal(plaintext)
            val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
            val body = Base64.encodeToString(ciphertext, Base64.NO_WRAP)
            "$iv:$body"
        } finally {
            plaintext.fill(0)
        }
    }

    private fun decrypt(encoded: String, key: SecretKey = existingCredentialKey()): String {
        val parts = encoded.split(':', limit = 2)
        require(parts.size == 2) { "Invalid encrypted credential format" }
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val ciphertext = Base64.decode(parts[1], Base64.NO_WRAP)
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            val plaintext = cipher.doFinal(ciphertext)
            try {
                plaintext.toString(Charsets.UTF_8)
            } finally {
                plaintext.fill(0)
            }
        } finally {
            iv.fill(0)
            ciphertext.fill(0)
        }
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun profileKey(id: String, field: String) = "profile.$id.$field"
    private fun secretKey(id: String) = "secret.$id"

    companion object {
        private const val PREFS_NAME = "apl_mobile_profiles_v1"
        private const val KEY_PROFILE_IDS = "profile_ids"
        private const val KEY_ACTIVE_ID = "active_profile_id"
        private const val KEY_AUTO_SELECTION = "auto_profile_selection"
        private const val KEY_LAST_AUTO_ID = "last_auto_profile_id"
        private const val KEY_PRIMARY_ID = "pool_primary_profile_id"
        private const val KEY_RESTORE_POLICY = "pool_restore_policy"
        private const val KEY_RECENTLY_FAILED_ID = "pool_recently_failed_profile_id"
        private const val KEY_RECENTLY_FAILED_AT = "pool_recently_failed_at"
        private const val KEY_LAST_FAILOVER_AT = "pool_last_failover_at"
        private const val KEY_VPN_PROCESS_RESTART_PENDING = "vpn_process_restart_pending"
        private const val KEY_SITE_EXCLUSIONS = "site_exclusions"
        private const val KEY_APP_EXCLUSIONS = "app_exclusions"
        private const val LEGACY_GATEWAY_LOCATION_ID = "active_free_location_id"
        private const val LEGACY_GATEWAY_LOCATION_LABEL = "active_free_location_label"
        private const val LEGACY_GATEWAY_RECOVERY_WINDOW = "free_recovery_window_started_at"
        private const val LEGACY_GATEWAY_RECOVERY_ATTEMPT = "free_recovery_attempt_count"
        private const val KEY_ALIAS = "ru.arvectum.proxylauncher.proxy_credentials.v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val MANAGED_JOURNAL_ALIAS = "ru.arvectum.proxylauncher.managed_rollback.v1"
        private const val MANAGED_EVIDENCE_ALIAS = "ru.arvectum.proxylauncher.managed_evidence.v1"
        @Volatile private var managedRecoveryRequired = false
    }
}
