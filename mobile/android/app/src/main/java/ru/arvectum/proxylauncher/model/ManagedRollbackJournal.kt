package ru.arvectum.proxylauncher.model

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.OutputStream
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Encrypted, one-update journal: only changed rows, exact post-state fingerprint. */
internal class ManagedRollbackJournal private constructor(
    private val source: SavedSubscription,
    private val expectedAfter: ByteArray,
    private val previous: Map<String, ManagedProfileRow?>,
) {
    override fun toString() = "ManagedRollbackJournal(redacted)"

    fun restore(currentSource: SavedSubscription?, current: ManagedProfileState,
                foregroundDisconnected: Boolean): ManagedProfileState? {
        if (!foregroundDisconnected || currentSource != source ||
            !ManagedSubscriptionRefresh.validState(current) ||
            previous.keys.any { it in current.protectedIds } ||
            !MessageDigest.isEqual(expectedAfter, fingerprint(current))) return null
        val rows = current.rows.associateBy { it.profile.id }.toMutableMap()
        for ((id,row) in previous) {
            if (rows[id]?.let { it.owner != source.id } == true) return null
            if (row == null) rows.remove(id) else rows[id] = row
        }
        val result = ManagedProfileState(rows.values.toList(),current.selection)
        return result.takeIf(ManagedSubscriptionRefresh::validState)
    }

    fun seal(key: SecretKey): String {
        val out = BoundedBuffer()
        try {
        DataOutputStream(out).use { stream ->
            stream.writeInt(1)
            stream.writeUTF(source.id)
            stream.writeUTF(source.host)
            stream.writeLong(source.createdAt)
            stream.write(expectedAfter)
            stream.writeInt(previous.size)
            for ((id,row) in previous.toSortedMap()) {
                stream.writeUTF(id)
                stream.writeBoolean(row != null)
                if (row != null) writeRow(stream,row)
            }
        }
        val bytes = out.toByteArray()
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE,key)
            cipher.updateAAD(AAD)
            require(cipher.iv.size == 12)
            return Base64.getEncoder().encodeToString(cipher.iv + cipher.doFinal(bytes))
        } finally { bytes.fill(0) }
        } finally { out.wipe() }
    }

    companion object {
        const val MAX_BYTES = 2_097_152
        const val MAX_CHANGED = 400
        private val AAD = "apl-managed-rollback-journal-v1".toByteArray(Charsets.UTF_8)

        fun from(transaction: ManagedRefreshTransaction): ManagedRollbackJournal {
            val before = transaction.before.rows.associateBy { it.profile.id }
            val after = transaction.after.rows.associateBy { it.profile.id }
            require(ManagedSubscriptionRefresh.validState(transaction.before) &&
                ManagedSubscriptionRefresh.validState(transaction.after) &&
                transaction.before.selection == transaction.after.selection)
            val changed = (before.keys + after.keys).filter { before[it] != after[it] }.toSet()
            require(changed == transaction.changedIds && changed.size in 1..MAX_CHANGED)
            require(changed.none { it in transaction.before.protectedIds })
            require(changed.all { id ->
                (before[id] == null || before[id]?.owner == transaction.source.id) &&
                (after[id] == null || after[id]?.owner == transaction.source.id)
            })
            return ManagedRollbackJournal(transaction.source,fingerprint(transaction.after),changed.associateWith { before[it] })
        }

        fun open(encoded: String, key: SecretKey): ManagedRollbackJournal {
            require(encoded.length <= (MAX_BYTES+30)/3*4+4)
            val bytes = Base64.getDecoder().decode(encoded)
            require(bytes.size in 29..(MAX_BYTES+28))
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE,key,GCMParameterSpec(128,bytes,0,12))
            cipher.updateAAD(AAD)
            val plain = try { cipher.doFinal(bytes,12,bytes.size-12) } finally { bytes.fill(0) }
            try {
                return DataInputStream(ByteArrayInputStream(plain)).use { input ->
                    require(input.readInt() == 1)
                    val source = SavedSubscription(input.readUTF(),input.readUTF(),input.readLong())
                    require(java.util.UUID.fromString(source.id).toString() == source.id &&
                        source.createdAt >= 0 && ProxySubscriptionImport.source("https://${source.host}/")?.host == source.host)
                    val digest = ByteArray(32).also(input::readFully)
                    val size = input.readInt()
                    require(size in 1..MAX_CHANGED)
                    val previous = linkedMapOf<String,ManagedProfileRow?>()
                    repeat(size) {
                        val id = input.readUTF()
                        require(id.isNotBlank() && !previous.containsKey(id))
                        val row = if (input.readBoolean()) readRow(input) else null
                        require(row == null || row.profile.id == id && row.owner == source.id)
                        previous[id] = row
                    }
                    require(input.read() == -1)
                    ManagedRollbackJournal(source,digest,previous)
                }
            } finally { plain.fill(0) }
        }

        private fun fingerprint(state: ManagedProfileState): ByteArray {
            val digest = MessageDigest.getInstance("SHA-256")
            DataOutputStream(DigestOutputStream(object : OutputStream() {
                override fun write(b: Int) = Unit
                override fun write(b: ByteArray, off: Int, len: Int) = Unit
            },digest)).use { out ->
                out.writeInt(1)
                val s = state.selection
                listOf(s.active,s.primary,s.lastAuto,s.selected,s.recentlyFailed).forEach { writeNullable(out,it) }
                out.writeBoolean(s.auto)
                out.writeInt(state.rows.size)
                state.rows.forEach { writeRow(out,it) }
            }
            return digest.digest()
        }

        private fun writeNullable(out: DataOutputStream, value: String?) {
            out.writeBoolean(value != null)
            if (value != null) out.writeUTF(value)
        }
        private fun readNullable(input: DataInputStream): String? = if (input.readBoolean()) input.readUTF() else null

        private fun writeRow(out: DataOutputStream, row: ManagedProfileRow) {
            val p = row.profile
            out.writeUTF(p.id)
            out.writeUTF(p.name)
            out.writeUTF(p.host)
            out.writeInt(p.port)
            out.writeUTF(p.type.name)
            writeNullable(out,p.username)
            writeNullable(out,p.passwordRef)
            writeNullable(out,row.owner)
            writeNullable(out,row.encryptedCredential)
        }
        private fun readRow(input: DataInputStream): ManagedProfileRow {
            val p = ProxyProfile(input.readUTF(),input.readUTF(),input.readUTF(),input.readInt(),
                ProxyType.valueOf(input.readUTF()),readNullable(input),readNullable(input))
            val row = ManagedProfileRow(p,readNullable(input),readNullable(input))
            require(ManagedSubscriptionRefresh.validState(ManagedProfileState(listOf(row),
                ManagedSelection(null,null,null,null,null,false))))
            return row
        }

        private class BoundedBuffer : ByteArrayOutputStream() {
            override fun write(b: Int) { require(size() < MAX_BYTES); super.write(b) }
            override fun write(b: ByteArray, off: Int, len: Int) {
                require(len >= 0 && len <= MAX_BYTES - size())
                super.write(b,off,len)
            }
            fun wipe() { buf.fill(0);reset() }
        }
    }
}
