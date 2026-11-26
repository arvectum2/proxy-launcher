package ru.arvectum.proxylauncher.storage

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import ru.arvectum.proxylauncher.model.SavedSubscription
import ru.arvectum.proxylauncher.model.SavedSubscriptionCatalog
import ru.arvectum.proxylauncher.model.SavedSubscriptionEntry

/** Main-process UI store; catalog is a single bounded preference commit. */
class SecureSubscriptionStore(context: Context) {
    private val prefs = context.getSharedPreferences("apl_saved_subscriptions_v1",Context.MODE_PRIVATE)

    private fun entries(): List<SavedSubscriptionEntry> =
        prefs.getString(CATALOG,null)?.let(SavedSubscriptionCatalog::decode).orEmpty()

    fun list(): List<SavedSubscription> = synchronized(lock) { entries().map { it.metadata } }

    fun add(raw: String): SavedSubscription = synchronized(lock) {
        val old = entries()
        require(old.size < SavedSubscriptionCatalog.MAX_SOURCES)
        val meta = SavedSubscriptionCatalog.metadata(raw,System.currentTimeMillis())
        val entry = SavedSubscriptionCatalog.seal(meta,raw,key(allowCreate = old.isEmpty()))
        commit(old+entry)
        meta
    }

    fun source(expected: SavedSubscription): String = synchronized(lock) {
        val entry = entries().singleOrNull { it.metadata == expected } ?: error("Saved source changed")
        SavedSubscriptionCatalog.open(entry,key(allowCreate = false))
    }

    fun contains(expected: SavedSubscription): Boolean = synchronized(lock) {
        entries().any { it.metadata == expected }
    }

    fun remove(expected: SavedSubscription): Boolean = synchronized(lock) {
        val old = entries()
        if (old.none { it.metadata == expected }) return@synchronized false
        commit(old.filterNot { it.metadata == expected })
        true
    }

    private fun commit(updated: List<SavedSubscriptionEntry>) {
        val previous = prefs.getString(CATALOG,null)
        val encoded = SavedSubscriptionCatalog.encode(updated)
        if (!prefs.edit().putString(CATALOG,encoded).commit()) {
            val rollback = prefs.edit()
            if (previous == null) rollback.remove(CATALOG) else rollback.putString(CATALOG,previous)
            check(rollback.commit()) { "Subscription storage recovery failed" }
            error("Subscription storage failed")
        }
    }

    private fun key(allowCreate: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS,null) as? SecretKey)?.let { return it }
        check(allowCreate) { "Subscription key unavailable" }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build())
        return generator.generateKey()
    }

    private companion object {
        const val CATALOG = "catalog"
        const val ALIAS = "ru.arvectum.proxylauncher.subscription_sources.v1"
        val lock = Any()
    }
}
