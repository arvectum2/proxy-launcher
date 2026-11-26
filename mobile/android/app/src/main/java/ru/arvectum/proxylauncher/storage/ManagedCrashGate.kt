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
    fun acquire(): Acquisition {
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
            if (!Files.notExists(markerPath, LinkOption.NOFOLLOW_LINKS))
                return Acquisition(Status.RECOVERY_REQUIRED)
            val lease = Lease(channel, lock, canonical, markerPath, syncDirectory) { synchronized(heldPaths) { heldPaths.remove(lockPath) } }
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
        private val releaseReservation: () -> Unit,
    ) : AutoCloseable {
        private var closed = false
        private var started = false
        private var resolved = false
        private var markerDurable = false
        private fun usable() = !closed && channel.isOpen && lock.isValid

        /** No data or credentials in the marker. Never overwrite an existing marker. */
        @Synchronized
        fun beginMutation(): Boolean {
            if (!usable() || started || resolved) return false
            started = true
            return try {
                FileChannel.open(marker, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE,
                    LinkOption.NOFOLLOW_LINKS).use { file ->
                    val bytes = ByteBuffer.wrap("APL-MANAGED-PENDING-v1\n".toByteArray(Charsets.US_ASCII))
                    while (bytes.hasRemaining()) file.write(bytes)
                    file.force(true)
                }
                syncDirectory(directory)
                markerDurable = true
                true
            } catch (_: Exception) { false }
        }

        /**
         * Only caller-supplied *durable* verification authorizes marker removal.
         * A preference cache readback alone is not proof. If deletion sync fails,
         * recreate the blocker where possible; report failure regardless.
         */
        @Synchronized
        fun resolve(verifyDurableOutcome: () -> Boolean): Boolean {
            if (!usable() || !started || !markerDurable || resolved ||
                !runCatching(verifyDurableOutcome).getOrDefault(false)) return false
            return try {
                Files.delete(marker)
                syncDirectory(directory)
                resolved = true
                true
            } catch (_: Exception) {
                runCatching {
                    FileChannel.open(marker, StandardOpenOption.CREATE, StandardOpenOption.WRITE,
                        LinkOption.NOFOLLOW_LINKS).use { file -> file.force(true) }
                    syncDirectory(directory)
                }
                false
            }
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
