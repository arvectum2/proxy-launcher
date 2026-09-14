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
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType
import ru.arvectum.proxylauncher.tunnel.ProxyVpnService

data class ResolvedProxyProfile(
    val profile: ProxyProfile,
    val password: String?,
)

class SecureProfileStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun saveActive(profile: ProxyProfile, password: CharArray?) {
        val passwordRef = if (password != null) {
            prefs.edit().putString(secretKey(profile.id), encrypt(password)).apply()
            "android-keystore:${profile.id}"
        } else {
            prefs.edit().remove(secretKey(profile.id)).apply()
            null
        }

        prefs.edit()
            .putString(KEY_ACTIVE_ID, profile.id)
            .putString(profileKey(profile.id, "name"), profile.name)
            .putString(profileKey(profile.id, "host"), profile.host)
            .putInt(profileKey(profile.id, "port"), profile.port)
            .putString(profileKey(profile.id, "type"), profile.type.name)
            .putString(profileKey(profile.id, "username"), profile.username)
            .putString(profileKey(profile.id, "password_ref"), passwordRef)
            .apply()
    }

    fun loadActive(): ResolvedProxyProfile? {
        val id = prefs.getString(KEY_ACTIVE_ID, null) ?: return null
        val host = prefs.getString(profileKey(id, "host"), null) ?: return null
        val port = prefs.getInt(profileKey(id, "port"), -1)
        val type = runCatching {
            ProxyType.valueOf(prefs.getString(profileKey(id, "type"), ProxyType.SOCKS5.name)!!)
        }.getOrDefault(ProxyType.SOCKS5)
        val passwordRef = prefs.getString(profileKey(id, "password_ref"), null)
        val profile = ProxyProfile(
            id = id,
            name = prefs.getString(profileKey(id, "name"), "$host:$port") ?: "$host:$port",
            host = host,
            port = port,
            type = type,
            username = prefs.getString(profileKey(id, "username"), null),
            passwordRef = passwordRef,
        )
        val password = if (passwordRef != null) {
            val encrypted = prefs.getString(secretKey(id), null)
                ?: error("Encrypted password is missing")
            decrypt(encrypted)
        } else {
            null
        }
        return ResolvedProxyProfile(profile, password)
    }

    fun setLastState(state: String, detail: String? = null) {
        prefs.edit().putString(KEY_LAST_STATE, state).putString(KEY_LAST_DETAIL, detail).apply()
    }

    fun getLastState(): String = prefs.getString(KEY_LAST_STATE, ProxyVpnService.STATE_DISCONNECTED)
        ?: ProxyVpnService.STATE_DISCONNECTED

    fun getLastDetail(): String? = prefs.getString(KEY_LAST_DETAIL, null)

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

    companion object {
        private const val PREFS_NAME = "apl_mobile_profiles_v1"
        private const val KEY_ACTIVE_ID = "active_profile_id"
        private const val KEY_LAST_STATE = "tunnel_state"
        private const val KEY_LAST_DETAIL = "tunnel_detail"
        private const val KEY_ALIAS = "ru.arvectum.proxylauncher.proxy_credentials.v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
