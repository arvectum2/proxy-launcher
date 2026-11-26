package ru.arvectum.proxylauncher.model

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.util.Base64
import java.util.Locale
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class SavedSubscription(val id: String, val host: String, val createdAt: Long)

internal class SavedSubscriptionEntry(val metadata: SavedSubscription, val encrypted: String) {
    override fun toString() = "SavedSubscriptionEntry(redacted)"
}

internal object SavedSubscriptionCatalog {
    const val MAX_SOURCES = 12
    const val MAX_CATALOG_BYTES = 65_536
    private const val MAX_ENCRYPTED = 4096

    private fun validate(meta: SavedSubscription) {
        require(UUID.fromString(meta.id).toString() == meta.id)
        require(meta.createdAt >= 0 && meta.host == meta.host.lowercase(Locale.ROOT))
        require(ProxySubscriptionImport.source("https://${meta.host}/")?.host == meta.host)
    }

    fun metadata(raw: String, now: Long): SavedSubscription {
        val source = requireNotNull(ProxySubscriptionImport.source(raw))
        return SavedSubscription(UUID.randomUUID().toString(), source.host.lowercase(Locale.ROOT), now)
            .also(::validate)
    }

    private fun aad(meta: SavedSubscription) =
        "apl-subscription-source-v1\n${meta.id}\n${meta.host}\n${meta.createdAt}".toByteArray(Charsets.UTF_8)

    fun seal(meta: SavedSubscription, raw: String, key: SecretKey): SavedSubscriptionEntry {
        validate(meta)
        val source = requireNotNull(ProxySubscriptionImport.source(raw))
        require(source.host.equals(meta.host,true))
        val plain = source.toASCIIString().toByteArray(Charsets.UTF_8)
        try {
            require(plain.size <= ProxySubscriptionImport.MAX_URL_BYTES)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE,key)
            cipher.updateAAD(aad(meta))
            require(cipher.iv.size == 12)
            return SavedSubscriptionEntry(meta,Base64.getEncoder().encodeToString(cipher.iv + cipher.doFinal(plain)))
        } finally { plain.fill(0) }
    }

    fun open(entry: SavedSubscriptionEntry, key: SecretKey): String {
        validate(entry.metadata)
        val bytes = encryptedBytes(entry.encrypted)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE,key,GCMParameterSpec(128,bytes,0,12))
            cipher.updateAAD(aad(entry.metadata))
            val plain = cipher.doFinal(bytes,12,bytes.size-12)
            try {
                val raw = ProxyBatchImport.readText(ByteArrayInputStream(plain)) ?: error("Invalid saved source")
                val uri = requireNotNull(ProxySubscriptionImport.source(raw))
                require(uri.host.equals(entry.metadata.host,true))
                return uri.toASCIIString()
            } finally { plain.fill(0) }
        } finally { bytes.fill(0) }
    }

    private fun encryptedBytes(encoded: String): ByteArray {
        require(encoded.length in 1..MAX_ENCRYPTED)
        return Base64.getDecoder().decode(encoded).also {
            require(it.size in 29..(12+16+ProxySubscriptionImport.MAX_URL_BYTES))
        }
    }

    fun encode(entries: List<SavedSubscriptionEntry>): String {
        require(entries.size <= MAX_SOURCES && entries.map { it.metadata.id }.toSet().size == entries.size)
        val out = ByteArrayOutputStream()
        DataOutputStream(out).use { stream ->
            stream.writeInt(1)
            stream.writeInt(entries.size)
            for (entry in entries) {
                validate(entry.metadata)
                encryptedBytes(entry.encrypted).fill(0)
                stream.writeUTF(entry.metadata.id)
                stream.writeUTF(entry.metadata.host)
                stream.writeLong(entry.metadata.createdAt)
                stream.writeUTF(entry.encrypted)
            }
        }
        require(out.size() <= MAX_CATALOG_BYTES)
        return Base64.getEncoder().encodeToString(out.toByteArray())
    }

    fun decode(encoded: String): List<SavedSubscriptionEntry> {
        require(encoded.length <= (MAX_CATALOG_BYTES+2)/3*4)
        val bytes = Base64.getDecoder().decode(encoded)
        require(bytes.size <= MAX_CATALOG_BYTES)
        return DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            require(input.readInt() == 1)
            val count = input.readInt()
            require(count in 0..MAX_SOURCES)
            val entries = List(count) {
                val meta = SavedSubscription(input.readUTF(),input.readUTF(),input.readLong())
                validate(meta)
                val encrypted = input.readUTF()
                encryptedBytes(encrypted).fill(0)
                SavedSubscriptionEntry(meta,encrypted)
            }
            require(input.read() == -1 && entries.map { it.metadata.id }.toSet().size == entries.size)
            entries
        }
    }
}
