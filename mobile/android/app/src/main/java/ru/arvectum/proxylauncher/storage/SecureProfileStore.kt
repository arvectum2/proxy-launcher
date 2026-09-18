package ru.arvectum.proxylauncher.storage

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONObject
import ru.arvectum.proxylauncher.model.PrimaryRestorePolicy
import ru.arvectum.proxylauncher.model.ProxyHealthSnapshot
import ru.arvectum.proxylauncher.model.ProxyHealthStatus
import ru.arvectum.proxylauncher.model.ProxyPoolEvent
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType
import ru.arvectum.proxylauncher.tunnel.ProxyVpnService

data class ResolvedProxyProfile(
    val profile: ProxyProfile,
    val password: String?,
)

class SecureProfileStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * Commit synchronously: the VPN service runs in a separate process so the active
     * profile must be on disk before Android starts that process.
     */
    fun saveActive(profile: ProxyProfile, password: CharArray?) {
        saveProfile(profile, password, makeActive = true)
    }

    fun saveProfile(profile: ProxyProfile, password: CharArray?, makeActive: Boolean = true) {
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

    fun listProfiles(): List<ProxyProfile> {
        ensureLegacyProfileIndexed()
        return profileIds()
            .mapNotNull(::loadProfileMetadata)
            .sortedWith(compareBy<ProxyProfile> { it.name.lowercase() }.thenBy { it.id })
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
        ensureLegacyProfileIndexed()
        check(prefs.edit().putBoolean(KEY_AUTO_SELECTION, enabled).commit()) {
            "Failed to persist Auto proxy selection"
        }
    }

    fun getLastAutoProfileId(): String? {
        ensureLegacyProfileIndexed()
        return prefs.getString(KEY_LAST_AUTO_ID, null)
    }

    fun setLastAutoProfileId(id: String?) {
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

    fun setActiveProfile(id: String) {
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
        ensureLegacyProfileIndexed()
        if (loadProfileMetadata(id) == null) return

        val remainingIds = profileIds().toMutableSet().apply { remove(id) }
        val nextActiveId = if (prefs.getString(KEY_ACTIVE_ID, null) == id) {
            remainingIds
                .mapNotNull(::loadProfileMetadata)
                .sortedWith(compareBy<ProxyProfile> { it.name.lowercase() }.thenBy { it.id })
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
                .sortedWith(compareBy<ProxyProfile> { it.name.lowercase() }.thenBy { it.id })
                .firstOrNull()
                ?.id
            if (nextPrimary == null) editor.remove(KEY_PRIMARY_ID)
            else editor.putString(KEY_PRIMARY_ID, nextPrimary)
        }
        if (prefs.getString(KEY_RECENTLY_FAILED_ID, null) == id) {
            editor.remove(KEY_RECENTLY_FAILED_ID).remove(KEY_RECENTLY_FAILED_AT)
        }
        editor.remove(healthKey(id, "status"))
            .remove(healthKey(id, "latency"))
            .remove(healthKey(id, "checked_at"))

        check(editor.commit()) { "Failed to delete proxy profile" }
    }

    fun setLastState(state: String, detail: String? = null) {
        prefs.edit().putString(KEY_LAST_STATE, state).putString(KEY_LAST_DETAIL, detail).commit()
    }

    fun getLastState(): String = prefs.getString(KEY_LAST_STATE, ProxyVpnService.STATE_DISCONNECTED)
        ?: ProxyVpnService.STATE_DISCONNECTED

    fun getLastDetail(): String? = prefs.getString(KEY_LAST_DETAIL, null)

    fun getPrimaryProfileId(): String? {
        ensureLegacyProfileIndexed()
        val stored = prefs.getString(KEY_PRIMARY_ID, null)
        if (stored != null && loadProfileMetadata(stored) != null) return stored
        return listProfiles().firstOrNull()?.id
    }

    fun setPrimaryProfileId(id: String) {
        ensureLegacyProfileIndexed()
        require(loadProfileMetadata(id) != null) { "Unknown proxy profile" }
        check(prefs.edit().putString(KEY_PRIMARY_ID, id).commit()) {
            "Failed to persist primary proxy"
        }
    }

    fun getRestorePolicy(): PrimaryRestorePolicy = runCatching {
        PrimaryRestorePolicy.valueOf(
            prefs.getString(KEY_RESTORE_POLICY, PrimaryRestorePolicy.STAY_ON_CURRENT.name)!!,
        )
    }.getOrDefault(PrimaryRestorePolicy.STAY_ON_CURRENT)

    fun setRestorePolicy(policy: PrimaryRestorePolicy) {
        check(prefs.edit().putString(KEY_RESTORE_POLICY, policy.name).commit()) {
            "Failed to persist primary restore policy"
        }
    }

    fun setHealth(
        profileId: String,
        status: ProxyHealthStatus,
        latencyMs: Long?,
        checkedAtMs: Long = System.currentTimeMillis(),
    ) {
        if (loadProfileMetadata(profileId) == null) return
        val editor = prefs.edit()
            .putString(healthKey(profileId, "status"), status.name)
            .putLong(healthKey(profileId, "checked_at"), checkedAtMs)
        if (latencyMs == null) editor.remove(healthKey(profileId, "latency"))
        else editor.putLong(healthKey(profileId, "latency"), latencyMs.coerceAtLeast(0L))
        editor.commit()
    }

    fun getHealth(profileId: String): ProxyHealthSnapshot? {
        if (loadProfileMetadata(profileId) == null) return null
        val statusName = prefs.getString(healthKey(profileId, "status"), null) ?: return null
        val status = runCatching { ProxyHealthStatus.valueOf(statusName) }
            .getOrDefault(ProxyHealthStatus.UNKNOWN)
        val latency = if (prefs.contains(healthKey(profileId, "latency"))) {
            prefs.getLong(healthKey(profileId, "latency"), 0L)
        } else null
        return ProxyHealthSnapshot(
            profileId = profileId,
            status = status,
            latencyMs = latency,
            checkedAtMs = prefs.getLong(healthKey(profileId, "checked_at"), 0L),
        )
    }

    fun markRecentlyFailedProfile(id: String, atMs: Long = System.currentTimeMillis()) {
        check(
            prefs.edit()
                .putString(KEY_RECENTLY_FAILED_ID, id)
                .putLong(KEY_RECENTLY_FAILED_AT, atMs)
                .commit(),
        ) { "Failed to persist failed proxy state" }
    }

    fun getRecentlyFailedProfileId(): String? = prefs.getString(KEY_RECENTLY_FAILED_ID, null)

    fun getRecentlyFailedAtMs(): Long = prefs.getLong(KEY_RECENTLY_FAILED_AT, 0L)

    fun clearRecentlyFailedProfile() {
        prefs.edit().remove(KEY_RECENTLY_FAILED_ID).remove(KEY_RECENTLY_FAILED_AT).commit()
    }

    fun setLastFailoverAtMs(value: Long) {
        prefs.edit().putLong(KEY_LAST_FAILOVER_AT, value).commit()
    }

    fun getLastFailoverAtMs(): Long = prefs.getLong(KEY_LAST_FAILOVER_AT, 0L)

    fun markFailoverRestartPending() {
        prefs.edit().putBoolean(KEY_FAILOVER_RESTART_PENDING, true).commit()
    }

    fun consumeFailoverRestartPending(): Boolean {
        val pending = prefs.getBoolean(KEY_FAILOVER_RESTART_PENDING, false)
        if (pending) prefs.edit().putBoolean(KEY_FAILOVER_RESTART_PENDING, false).commit()
        return pending
    }

    fun appendPoolEvent(
        type: String,
        profileId: String?,
        profileName: String?,
        detail: String? = null,
        timestampMs: Long = System.currentTimeMillis(),
    ) {
        val events = runCatching { JSONArray(prefs.getString(KEY_POOL_EVENTS, "[]")) }
            .getOrDefault(JSONArray())
        val item = JSONObject()
            .put("timestamp", timestampMs)
            .put("type", type.take(40))
            .put("profile_id", profileId ?: JSONObject.NULL)
            .put("profile_name", profileName?.take(80) ?: JSONObject.NULL)
            .put("detail", detail?.take(100) ?: JSONObject.NULL)
        val compact = JSONArray()
        val start = (events.length() - (MAX_POOL_EVENTS - 1)).coerceAtLeast(0)
        for (index in start until events.length()) compact.put(events.optJSONObject(index))
        compact.put(item)
        prefs.edit().putString(KEY_POOL_EVENTS, compact.toString()).commit()
    }

    fun listPoolEvents(limit: Int = 20): List<ProxyPoolEvent> {
        val events = runCatching { JSONArray(prefs.getString(KEY_POOL_EVENTS, "[]")) }
            .getOrDefault(JSONArray())
        val start = (events.length() - limit.coerceIn(1, MAX_POOL_EVENTS)).coerceAtLeast(0)
        return (events.length() - 1 downTo start).mapNotNull { index ->
            events.optJSONObject(index)?.let { item ->
                ProxyPoolEvent(
                    timestampMs = item.optLong("timestamp", 0L),
                    type = item.optString("type", "event"),
                    profileId = item.optNullableString("profile_id"),
                    profileName = item.optNullableString("profile_name"),
                    detail = item.optNullableString("detail"),
                )
            }
        }
    }

    private fun JSONObject.optNullableString(key: String): String? =
        if (isNull(key)) null else optString(key).takeIf { it.isNotBlank() }

    private fun ensureLegacyProfileIndexed() {
        if (prefs.contains(KEY_PROFILE_IDS)) return

        val activeId = prefs.getString(KEY_ACTIVE_ID, null)
        val legacyIds = if (
            activeId != null &&
            prefs.getString(profileKey(activeId, "host"), null) != null
        ) {
            setOf(activeId)
        } else {
            emptySet()
        }

        check(prefs.edit().putStringSet(KEY_PROFILE_IDS, legacyIds).commit()) {
            "Failed to initialize proxy profile index"
        }
    }

    private fun profileIds(): Set<String> =
        prefs.getStringSet(KEY_PROFILE_IDS, emptySet())?.toSet().orEmpty()

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

    private fun encrypt(value: CharArray): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
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

    private fun decrypt(encoded: String): String {
        val parts = encoded.split(':', limit = 2)
        require(parts.size == 2) { "Invalid encrypted credential format" }
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val ciphertext = Base64.decode(parts[1], Base64.NO_WRAP)
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
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
    private fun healthKey(id: String, field: String) = "health.$id.$field"

    companion object {
        private const val PREFS_NAME = "apl_mobile_profiles_v1"
        private const val KEY_PROFILE_IDS = "profile_ids"
        private const val KEY_ACTIVE_ID = "active_profile_id"
        private const val KEY_AUTO_SELECTION = "auto_profile_selection"
        private const val KEY_LAST_AUTO_ID = "last_auto_profile_id"
        private const val KEY_LAST_STATE = "tunnel_state"
        private const val KEY_LAST_DETAIL = "tunnel_detail"
        private const val KEY_PRIMARY_ID = "pool_primary_profile_id"
        private const val KEY_RESTORE_POLICY = "pool_restore_policy"
        private const val KEY_RECENTLY_FAILED_ID = "pool_recently_failed_profile_id"
        private const val KEY_RECENTLY_FAILED_AT = "pool_recently_failed_at"
        private const val KEY_LAST_FAILOVER_AT = "pool_last_failover_at"
        private const val KEY_FAILOVER_RESTART_PENDING = "pool_failover_restart_pending"
        private const val KEY_POOL_EVENTS = "pool_events_v1"
        private const val MAX_POOL_EVENTS = 40
        private const val KEY_ALIAS = "ru.arvectum.proxylauncher.proxy_credentials.v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
