package ru.arvectum.proxylauncher.storage

import java.io.DataOutputStream
import java.io.OutputStream
import java.security.DigestOutputStream
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Authenticated pre/post fingerprints; no profile data or tokens in the crash marker. */
internal class ManagedRecoveryEvidence private constructor(
    private val before: ByteArray,
    private val after: ByteArray,
) {
    enum class State { BEFORE, AFTER, UNKNOWN }

    fun classify(actual: Map<String,Any>): State {
        val digest=runCatching { fingerprint(actual) }.getOrNull() ?: return State.UNKNOWN
        return when {
            MessageDigest.isEqual(before,digest) -> State.BEFORE
            MessageDigest.isEqual(after,digest) -> State.AFTER
            else -> State.UNKNOWN
        }
    }

    fun seal(key: SecretKey): ByteArray {
        val plain=byteArrayOf(1)+before+after
        return try {
            val cipher=Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE,key)
            cipher.updateAAD(AAD)
            require(cipher.iv.size==12)
            cipher.iv+cipher.doFinal(plain)
        } finally { plain.fill(0) }
    }

    companion object {
        private val AAD="apl-managed-recovery-evidence-v1".toByteArray(Charsets.UTF_8)
        const val SEALED_SIZE=93

        fun create(before: Map<String,Any>, after: Map<String,Any>): ManagedRecoveryEvidence {
            val a=fingerprint(before)
            val b=fingerprint(after)
            require(!MessageDigest.isEqual(a,b))
            return ManagedRecoveryEvidence(a,b)
        }

        fun open(payload: ByteArray,key: SecretKey): ManagedRecoveryEvidence {
            require(payload.size==SEALED_SIZE)
            val cipher=Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE,key,GCMParameterSpec(128,payload,0,12))
            cipher.updateAAD(AAD)
            val plain=cipher.doFinal(payload,12,payload.size-12)
            try {
                require(plain.size==65 && plain[0]==1.toByte())
                val before=plain.copyOfRange(1,33)
                val after=plain.copyOfRange(33,65)
                require(!MessageDigest.isEqual(before,after))
                return ManagedRecoveryEvidence(before,after)
            } finally { plain.fill(0) }
        }

        /** Canonical type-tagged, length-prefixed UTF-8 (including long journal strings). */
        private fun fingerprint(values: Map<String,Any>): ByteArray {
            require(values.size<=ManagedPreferenceDiskVerifier.MAX_KEYS)
            val digest=MessageDigest.getInstance("SHA-256")
            DataOutputStream(DigestOutputStream(object:OutputStream(){
                override fun write(b:Int)=Unit
                override fun write(b:ByteArray,off:Int,len:Int)=Unit
            },digest)).use { out ->
                var total=0L
                fun text(value:String) {
                    require(value.length<=ManagedPreferenceDiskVerifier.MAX_BYTES &&
                        Charsets.UTF_8.newEncoder().canEncode(value))
                    val bytes=value.toByteArray(Charsets.UTF_8)
                    try {
                        total+=bytes.size
                        require(total<=ManagedPreferenceDiskVerifier.MAX_BYTES)
                        out.writeInt(bytes.size)
                        out.write(bytes)
                    } finally { bytes.fill(0) }
                }
                out.writeInt(1)
                out.writeInt(values.size)
                for ((key,value) in values.toSortedMap()) {
                    text(key)
                    when(value) {
                        is String -> { out.writeByte(1);text(value) }
                        is Int -> { out.writeByte(2);out.writeInt(value) }
                        is Long -> { out.writeByte(3);out.writeLong(value) }
                        is Boolean -> { out.writeByte(4);out.writeBoolean(value) }
                        is Float -> { require(value.isFinite());out.writeByte(5);out.writeFloat(value) }
                        is Set<*> -> {
                            require(value.size<=ManagedPreferenceDiskVerifier.MAX_KEYS && value.all { it is String })
                            out.writeByte(6);out.writeInt(value.size)
                            value.map { it as String }.sorted().forEach(::text)
                        }
                        else -> error("Unsupported preference type")
                    }
                }
            }
            return digest.digest()
        }
    }
}
