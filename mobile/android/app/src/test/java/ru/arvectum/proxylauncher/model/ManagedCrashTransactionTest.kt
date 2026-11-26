package ru.arvectum.proxylauncher.model

import java.nio.file.Files
import java.nio.file.Path
import org.junit.Assert.*
import org.junit.Test
import ru.arvectum.proxylauncher.storage.ManagedCrashGate
import ru.arvectum.proxylauncher.storage.ManagedCrashTransaction
import ru.arvectum.proxylauncher.storage.ManagedCrashTransaction.Outcome
import ru.arvectum.proxylauncher.storage.ManagedPreferenceBackend

class ManagedCrashTransactionTest {
    private fun withDirectory(block: (Path) -> Unit) {
        val dir=Files.createTempDirectory("apl-crash-transaction-")
        try { block(dir) } finally { dir.toFile().deleteRecursively() }
    }
    private val old=mapOf<String,Any>("secret.profile" to "old-cipher","profile_ids" to setOf("profile"))
    private val patch=mapOf<String,Any?>("secret.profile" to "new-cipher","managed_rollback_v1" to "encrypted-journal")
    private val next=old+patch.mapValues { it.value!! }
    private class Backend(val initial: Map<String,Any>, val write: (Int,Map<String,Any?>)->Boolean) : ManagedPreferenceBackend {
        var cache=initial
        var disk=initial
        var calls=0
        override fun read()=cache
        override fun commit(patch:Map<String,Any?>):Boolean {
            calls++
            cache=cache.toMutableMap().apply { patch.forEach{(k,v)->if(v==null) remove(k) else put(k,v)} }
            if(write(calls,patch)) { disk=cache;return true }
            return false
        }
    }

    @Test fun markerExistsBeforeWriteAndClearsAfterDurableReadback() = withDirectory { dir ->
        val b=Backend(old){_,_->assertTrue(Files.exists(dir.resolve("managed.pending")));true}
        val gate=ManagedCrashGate(dir)
        val tx=ManagedCrashTransaction(gate,b){b.disk==it}
        assertEquals(Outcome.APPLIED,tx.execute(old,patch){true})
        assertEquals(next,b.disk)
        assertFalse(Files.exists(dir.resolve("managed.pending")))
        gate.acquire().lease!!.close()
    }

    @Test fun cacheSuccessWithoutDurableProofRetainsMarkerAcrossRestart() = withDirectory { dir ->
        val b=Backend(old){_,_->true}
        val tx=ManagedCrashTransaction(ManagedCrashGate(dir),b){it==old}
        assertEquals(Outcome.RECOVERY_REQUIRED,tx.execute(old,patch){true})
        assertEquals(next,b.cache)
        val restarted=ManagedCrashTransaction(ManagedCrashGate(dir),b){true}
        assertEquals(Outcome.RECOVERY_REQUIRED,restarted.execute(next,patch){true})
        assertEquals(1,b.calls)
    }

    @Test fun verifiedRestorationClearsButFailedRestorationDoesNot() = withDirectory { dir ->
        val good=Backend(old){n,_->n>1}
        assertEquals(Outcome.RESTORED,ManagedCrashTransaction(ManagedCrashGate(dir),good){good.disk==it}.execute(old,patch){true})
        assertEquals(old,good.disk)
        assertFalse(Files.exists(dir.resolve("managed.pending")))
        val bad=Backend(old){_,_->false}
        assertEquals(Outcome.RECOVERY_REQUIRED,ManagedCrashTransaction(ManagedCrashGate(dir),bad){bad.disk==it}.execute(old,patch){true})
        assertTrue(Files.exists(dir.resolve("managed.pending")))
    }

    @Test fun busyStaleAndMarkerSyncFailureNeverWrite() = withDirectory { dir ->
        val b=Backend(old){_,_->fail("unexpected write");false}
        val gate=ManagedCrashGate(dir)
        gate.acquire().lease!!.use {
            assertEquals(Outcome.BUSY,ManagedCrashTransaction(gate,b){true}.execute(old,patch){true})
        }
        assertEquals(Outcome.STALE,ManagedCrashTransaction(gate,b){false}.execute(old,patch){true})
        assertEquals(Outcome.STALE,ManagedCrashTransaction(gate,b){true}.execute(old,patch){false})
        val broken=ManagedCrashGate(dir){error("Synthetic directory sync failure")}
        assertEquals(Outcome.RECOVERY_REQUIRED,ManagedCrashTransaction(broken,b){true}.execute(old,patch){true})
        assertEquals(0,b.calls)
    }
}
