package ru.arvectum.proxylauncher.storage

import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.StandardOpenOption

/**
 * Private-directory exclusion primitive. Every participant must use the same stable lock
 * inode; never unlink the lock file. An abandoned marker is an explicit recovery blocker,
 * not evidence that a preference commit did or did not reach disk.
 */
internal class ManagedCrashGate(
    private val directory: Path,
    private val syncDirectory: (Path) -> Unit = { dir ->
        FileChannel.open(dir, StandardOpenOption.READ).use { it.force(true) }
    },
) {
    enum class Status { ACQUIRED, BUSY, RECOVERY_REQUIRED, UNAVAILABLE }
    class Acquisition(val status: Status, val lease: Lease? = null)

    private companion object {
        // Never open a competing channel in this JVM: on POSIX closing another
        // descriptor for the inode can release process-owned locks.
        val heldPaths = mutableSetOf<Path>()
    }

    /** Nonblocking; any uncertainty fails closed. */
    fun acquire(): Acquisition = acquireInternal(false)

    /** Read-only inspection of an abandoned marker, never clears it. */
    fun inspectPending(inspect: (ByteArray) -> ManagedRecoveryEvidence.State): ManagedRecoveryEvidence.State {
        val lease=acquireInternal(true).lease ?: return ManagedRecoveryEvidence.State.UNKNOWN
        return lease.use {
            runCatching { inspect(lease.readPending()) }.getOrDefault(ManagedRecoveryEvidence.State.UNKNOWN)
        }
    }

    /**
     * Explicit recovery confirmation only. Caller must authenticate the reviewed payload
     * and independently verify the exact durable state under this same exclusive lease.
     */
    internal fun acknowledgePending(expectedPayload: ByteArray, verify: (ByteArray) -> Boolean): Boolean {
        val lease=acquireInternal(true).lease ?: return false
        return lease.use {
            runCatching { lease.resolvePending(expectedPayload,verify) }.getOrDefault(false)
        }
    }

    private fun acquireInternal(recovery: Boolean): Acquisition {
        var channel: FileChannel? = null
        var lock: FileLock? = null
        var reserved: Path? = null
        try {
            val existed = Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)
            if (!existed) {
                val parent = directory.toAbsolutePath().parent ?: return Acquisition(Status.UNAVAILABLE)
                if (!Files.isDirectory(parent)) return Acquisition(Status.UNAVAILABLE)
                try { Files.createDirectory(directory) } catch (_: java.nio.file.FileAlreadyExistsException) { }
            }
            if (!Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)) return Acquisition(Status.UNAVAILABLE)
            val canonical = directory.toRealPath()
            if (!existed) syncDirectory(canonical.parent ?: return Acquisition(Status.UNAVAILABLE))
            val lockPath = canonical.resolve("managed.lock")
            val markerPath = canonical.resolve("managed.pending")
            if (!synchronized(heldPaths) { heldPaths.add(lockPath) }) return Acquisition(Status.BUSY)
            reserved = lockPath
            channel = FileChannel.open(lockPath, StandardOpenOption.CREATE, StandardOpenOption.WRITE,
                LinkOption.NOFOLLOW_LINKS)
            lock = channel.tryLock() ?: return Acquisition(Status.BUSY)
            // notExists is false on an indeterminate filesystem result as well.
            val absent = Files.notExists(markerPath, LinkOption.NOFOLLOW_LINKS)
            if (!recovery && !absent) return Acquisition(Status.RECOVERY_REQUIRED)
            if (recovery && absent) return Acquisition(Status.UNAVAILABLE)
            val lease = Lease(channel, lock, canonical, markerPath, syncDirectory, recovery) { synchronized(heldPaths) { heldPaths.remove(lockPath) } }
            channel = null
            lock = null
            reserved = null
            return Acquisition(Status.ACQUIRED, lease)
        } catch (_: java.nio.channels.OverlappingFileLockException) {
            return Acquisition(Status.BUSY)
        } catch (_: Exception) {
            return Acquisition(Status.UNAVAILABLE)
        } finally {
            runCatching { lock?.release() }
            runCatching { channel?.close() }
            reserved?.let { synchronized(heldPaths) { heldPaths.remove(it) } }
        }
    }

    class Lease internal constructor(
        private val channel: FileChannel,
        private val lock: FileLock,
        private val directory: Path,
        private val marker: Path,
        private val syncDirectory: (Path) -> Unit,
        private val recovery: Boolean,
        private val releaseReservation: () -> Unit,
    ) : AutoCloseable {
        private var closed = false
        private var started = false
        private var resolved = false
        private var markerDurable = false
        private fun usable() = !closed && channel.isOpen && lock.isValid

        @Synchronized
        internal fun isHeld(): Boolean = usable()

        /** Authenticated fingerprints only. Never overwrite an existing marker. */
        @Synchronized
        fun beginMutation(payload: ByteArray = "APL-MANAGED-PENDING-v1\n".toByteArray(Charsets.US_ASCII)): Boolean {
            if (recovery || !usable() || started || resolved || payload.isEmpty() || payload.size > 4096) return false
            started = true
            return try {
                FileChannel.open(marker, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE,
                    LinkOption.NOFOLLOW_LINKS).use { file ->
                    val bytes = ByteBuffer.wrap(payload)
                    while (bytes.hasRemaining()) require(file.write(bytes)>0)
                    file.force(true)
                }
                syncDirectory(directory)
                markerDurable = true
                true
            } catch (_: Exception) { false }
        }

        @Synchronized
        internal fun readPending(): ByteArray {
            check(recovery && usable())
            return readMarker()
        }

        private fun readMarker(): ByteArray {
            check(Files.isRegularFile(marker,LinkOption.NOFOLLOW_LINKS))
            return FileChannel.open(marker,StandardOpenOption.READ,LinkOption.NOFOLLOW_LINKS).use { file ->
                val size=file.size()
                require(size in 1..4096)
                val buffer=ByteBuffer.allocate(size.toInt())
                while(buffer.hasRemaining()) require(file.read(buffer)>0)
                require(file.size()==size && file.read(ByteBuffer.allocate(1)) == -1)
                buffer.array()
            }
        }

        @Synchronized
        internal fun resolvePending(expectedPayload: ByteArray, verify: (ByteArray) -> Boolean): Boolean {
            if (!recovery || !usable() || resolved) return false
            val actual=readPending()
            if (!java.security.MessageDigest.isEqual(expectedPayload,actual) ||
                !runCatching { verify(actual) }.getOrDefault(false)) return false
            return removeMarker(actual)
        }

        /**
         * Only caller-supplied *durable* verification authorizes marker removal.
         * A preference cache readback alone is not proof. If deletion sync fails,
         * recreate the blocker where possible; report failure regardless.
         */
        @Synchronized
        fun resolve(verifyDurableOutcome: () -> Boolean): Boolean {
            if (recovery || !usable() || !started || !markerDurable || resolved ||
                !runCatching(verifyDurableOutcome).getOrDefault(false)) return false
            // Preserve the original authenticated evidence if deletion cannot be synced.
            val original = runCatching { readMarker() }.getOrNull() ?: return false
            return removeMarker(original)
        }

        private fun removeMarker(original: ByteArray): Boolean = try {
            Files.delete(marker)
            syncDirectory(directory)
            resolved = true
            true
        } catch (_: Exception) {
            runCatching {
                if (Files.notExists(marker,LinkOption.NOFOLLOW_LINKS)) {
                    FileChannel.open(marker,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE,
                        LinkOption.NOFOLLOW_LINKS).use { file ->
                        val bytes=ByteBuffer.wrap(original)
                        while(bytes.hasRemaining()) require(file.write(bytes)>0)
                        file.force(true)
                    }
                    syncDirectory(directory)
                }
            }
            false
        }

        /** Releasing exclusion does not clear an unresolved marker. */
        @Synchronized
        override fun close() {
            if (closed) return
            closed = true
            try { lock.release() } finally {
                try { channel.close() } finally { releaseReservation() }
            }
        }
    }
}
