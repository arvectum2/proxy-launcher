package ru.arvectum.proxylauncher.model

import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import ru.arvectum.proxylauncher.storage.ManagedCrashGate
import ru.arvectum.proxylauncher.storage.ManagedCrashGate.Status
import ru.arvectum.proxylauncher.storage.ManagedVpnProcessLease

class ManagedCrashGateTest {
    private fun withDirectory(block: (Path) -> Unit) {
        val dir = Files.createTempDirectory("apl-crash-gate-")
        try { block(dir) } finally { dir.toFile().deleteRecursively() }
    }
    @Test fun stableLockAndNonReentrantLease() = withDirectory { dir ->
        val gate = ManagedCrashGate(dir)
        val acquired = gate.acquire()
        assertEquals(Status.ACQUIRED, acquired.status)
        acquired.lease!!.use {
            assertEquals(Status.BUSY, ManagedCrashGate(dir).acquire().status)
        }
        assertTrue(Files.exists(dir.resolve("managed.lock")))
        gate.acquire().lease!!.close()
    }

    @Test fun markerRequiresExplicitDurableEvidence() = withDirectory { dir ->
        val gate = ManagedCrashGate(dir)
        gate.acquire().lease!!.use { lease ->
            assertFalse(lease.resolve { true })
            assertTrue(lease.beginMutation())
            assertFalse(lease.beginMutation())
            assertFalse(lease.resolve { false })
            assertTrue(Files.exists(dir.resolve("managed.pending")))
            assertTrue(lease.resolve { true })
            assertFalse(lease.resolve { true })
        }
        assertFalse(Files.exists(dir.resolve("managed.pending")))
        gate.acquire().lease!!.close()
    }

    @Test fun abandonedAndMalformedMarkerBlockFreshInstance() = withDirectory { dir ->
        val gate = ManagedCrashGate(dir)
        gate.acquire().lease!!.use { assertTrue(it.beginMutation()) }
        assertEquals(Status.RECOVERY_REQUIRED, ManagedCrashGate(dir).acquire().status)
        Files.write(dir.resolve("managed.pending"), byteArrayOf())
        assertEquals(Status.RECOVERY_REQUIRED, gate.acquire().status)
    }

    @Test fun directorySyncFailureRetainsBlocker() = withDirectory { dir ->
        val gate = ManagedCrashGate(dir) { error("Synthetic sync failure") }
        gate.acquire().lease!!.use { assertFalse(it.beginMutation()); assertFalse(it.resolve { true }) }
        assertEquals(Status.RECOVERY_REQUIRED, ManagedCrashGate(dir).acquire().status)
    }

    @Test fun failedMarkerRemovalSyncRecreatesBlocker() = withDirectory { dir ->
        var syncs=0
        val gate=ManagedCrashGate(dir) { if (++syncs >= 2) error("Synthetic sync failure") }
        gate.acquire().lease!!.use {
            assertTrue(it.beginMutation())
            assertFalse(it.resolve { true })
        }
        assertEquals(Status.RECOVERY_REQUIRED, ManagedCrashGate(dir).acquire().status)
    }

    @Test fun repeatedLocalAttemptDoesNotReleaseOsLock() = withDirectory { dir ->
        val gate=ManagedCrashGate(dir)
        gate.acquire().lease!!.use {
            assertEquals(Status.BUSY,ManagedCrashGate(dir).acquire().status)
            val cp=listOf(CrashGateChild::class.java,ManagedCrashGate::class.java,kotlin.Unit::class.java)
                .map { java.io.File(requireNotNull(it.protectionDomain).codeSource.location.toURI()).path }
                .distinct().joinToString(java.io.File.pathSeparator)
            val java=java.io.File(System.getProperty("java.home"),"bin/java").path
            val child=ProcessBuilder(java,"-cp",cp,CrashGateChild::class.java.name,dir.toString(),"probe")
                .redirectErrorStream(true).start()
            try {
                assertTrue(child.waitFor(10,TimeUnit.SECONDS))
                assertEquals(0,child.exitValue())
                assertEquals("BUSY",child.inputStream.bufferedReader().readText().trim())
            } finally { child.destroyForcibly() }
        }
    }

    @Test fun vpnLeaseSurvivesServiceRecreationUntilProcessExit() = withDirectory { dir ->
        val cp = listOf(CrashGateChild::class.java, ManagedCrashGate::class.java, kotlin.Unit::class.java)
            .map { java.io.File(requireNotNull(it.protectionDomain).codeSource.location.toURI()).path }
            .distinct().joinToString(java.io.File.pathSeparator)
        val java = java.io.File(System.getProperty("java.home"), "bin/java").path
        val child = ProcessBuilder(java,"-cp",cp,CrashGateChild::class.java.name,dir.toString(),"vpn")
            .redirectErrorStream(true).start()
        try {
            val deadline = System.nanoTime()+TimeUnit.SECONDS.toNanos(10)
            while (!Files.exists(dir.resolve("child.ready")) && child.isAlive && System.nanoTime()<deadline)
                Thread.sleep(20)
            assertTrue(Files.exists(dir.resolve("child.ready")))
            assertEquals(Status.BUSY, ManagedCrashGate(dir).acquire().status)
            assertFalse(Files.exists(dir.resolve("managed.pending")))
            child.destroyForcibly()
            assertTrue(child.waitFor(10,TimeUnit.SECONDS))
            ManagedCrashGate(dir).acquire().lease!!.close()
        } finally { child.destroyForcibly(); child.waitFor(10,TimeUnit.SECONDS) }
    }

    @Test fun vpnCannotEnterWhileManagedMutationOrRecoveryIsPending() = withDirectory { dir ->
        val gate = ManagedCrashGate(dir)
        gate.acquire().lease!!.use {
            assertEquals(Status.BUSY, ManagedVpnProcessLease.enter(gate))
            assertTrue(it.beginMutation())
        }
        assertEquals(Status.RECOVERY_REQUIRED, ManagedVpnProcessLease.enter(gate))
    }

    @Test fun separateJvmContentionAndAbruptExit() = withDirectory { dir ->
        // Gradle's test worker classpath can be indirect. Resolve actual code source paths.
        val cp = listOf(CrashGateChild::class.java,ManagedCrashGate::class.java,kotlin.Unit::class.java)
            .map { java.io.File(requireNotNull(it.protectionDomain).codeSource.location.toURI()).path }
            .distinct().joinToString(java.io.File.pathSeparator)
        val java = java.io.File(System.getProperty("java.home"),"bin/java").path
        val child = ProcessBuilder(java,"-cp",cp,CrashGateChild::class.java.name,dir.toString())
            .redirectErrorStream(true).start()
        try {
            val deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(10)
            while (!Files.exists(dir.resolve("child.ready")) && child.isAlive && System.nanoTime()<deadline)
                Thread.sleep(20)
            assertTrue("Child did not acquire gate",Files.exists(dir.resolve("child.ready")))
            assertEquals(Status.BUSY,ManagedCrashGate(dir).acquire().status)
            child.destroyForcibly()
            assertTrue(child.waitFor(10,TimeUnit.SECONDS))
            assertEquals(Status.RECOVERY_REQUIRED,ManagedCrashGate(dir).acquire().status)
        } finally {
            child.destroyForcibly()
            child.waitFor(10,TimeUnit.SECONDS)
        }
    }
}

object CrashGateChild {
    @JvmStatic fun main(args: Array<String>) {
        val dir=Path.of(args[0])
        if (args.getOrNull(1)=="probe") {
            val result=ManagedCrashGate(dir).acquire()
            result.lease?.close()
            println(result.status.name)
            return
        }
        if (args.getOrNull(1)=="vpn") {
            check(ManagedVpnProcessLease.enter(ManagedCrashGate(dir)) == Status.ACQUIRED)
            // A new service instance enters the same process; it reuses the retained lease.
            check(ManagedVpnProcessLease.enter(ManagedCrashGate(dir)) == Status.ACQUIRED)
            Files.createFile(dir.resolve("child.ready"))
            Thread.sleep(60_000)
            return
        }
        val lease=checkNotNull(ManagedCrashGate(dir).acquire().lease)
        check(lease.beginMutation())
        Files.createFile(dir.resolve("child.ready"))
        // Parent forcibly terminates this disposable JVM without executing finally.
        Thread.sleep(60_000)
        lease.close()
    }
}
