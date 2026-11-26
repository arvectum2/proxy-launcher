package ru.arvectum.proxylauncher.model

import java.nio.file.Files
import java.nio.file.Path
import javax.crypto.KeyGenerator
import org.junit.Assert.*
import org.junit.Test
import ru.arvectum.proxylauncher.storage.ManagedCrashGate
import ru.arvectum.proxylauncher.storage.ManagedCrashTransaction
import ru.arvectum.proxylauncher.storage.ManagedPreferenceBackend
import ru.arvectum.proxylauncher.storage.ManagedPreferenceDiskVerifier
import ru.arvectum.proxylauncher.storage.ManagedRecoveryEvidence
import ru.arvectum.proxylauncher.storage.ManagedRecoveryReview
import ru.arvectum.proxylauncher.storage.ManagedRecoveryEvidence.State

class ManagedDiskRecoveryTest {
    private fun withFile(block:(Path)->Unit) {
        val dir=Files.createTempDirectory("apl-disk-recovery-")
        try { block(dir.resolve("profiles.xml")) } finally { dir.toFile().deleteRecursively() }
    }
    private fun write(file:Path,text:String) { Files.write(file,text.toByteArray(Charsets.UTF_8)) }
    private val expected=mapOf<String,Any>("text" to " p&雪 ", "port" to 443,"time" to 9L,
        "auto" to false,"float" to 1.5f,"ids" to setOf("a","b"),"empty" to "")
    private val xml="""<?xml version="1.0" encoding="utf-8" standalone="yes"?>
        <map><string name="text"> p&amp;雪 </string><int name="port" value="443"/>
        <long name="time" value="9"/><boolean name="auto" value="false"/>
        <float name="float" value="1.5"/><set name="ids"><string>b</string><string>a</string></set>
        <string name="empty"></string></map>"""
    private fun key()=KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
    private fun invalid(block:()->Unit) {
        try { block(); fail("Expected rejection") } catch (_:Exception) {}
    }

    @Test fun exactDiskReadIncludesAllTypesAndWhitespace() = withFile { f ->
        write(f,xml)
        val verifier=ManagedPreferenceDiskVerifier(f)
        assertEquals(expected,verifier.readVerified())
        assertTrue(verifier.matches(expected))
        assertFalse(verifier.matches(expected+("port" to 443L)))
        assertFalse(verifier.matches(expected- "empty"))
        assertFalse(verifier.matches(expected+("text" to "p&雪")))
    }

    @Test fun rejectsAmbiguousXmlAndExternalEntities() = withFile { f ->
        val v=ManagedPreferenceDiskVerifier(f)
        for (input in listOf(
            """<map><string name="a">one</string><string name="a">two</string></map>""",
            """<map><set name="a"><string>x</string><string>x</string></set></map>""",
            """<map><string name="a"><nested/></string></map>""",
            """<map><boolean name="a" value="TRUE"/></map>""",
            """<map><null name="a"/></map>""",
            """<map><int name="a" value="1" unknown="x"/></map>""",
            """<!DOCTYPE map [<!ENTITY x SYSTEM "file:///nonexistent">]><map><string name="a">&x;</string></map>""",
            """<map><string name="a">broken</map>""",
            """<other/>""",
            """<map><set name="a"><string name="unexpected">x</string></set></map>"""
        )) {
            write(f,input)
            assertFalse(v.matches(emptyMap()))
            invalid { v.readVerified() }
        }
        Files.write(f,byteArrayOf(0xc0.toByte(),0xaf.toByte()))
        invalid { v.readVerified() }
    }

    @Test fun backupSymlinkOversizeAndSyncFailureAreNotProof() = withFile { f ->
        write(f,xml)
        val v=ManagedPreferenceDiskVerifier(f)
        val backup=f.resolveSibling("profiles.xml.bak")
        write(backup,xml)
        assertFalse(v.matches(expected))
        Files.delete(backup)
        assertFalse(ManagedPreferenceDiskVerifier(f){error("sync failed")}.matches(expected))
        val target=f.resolveSibling("target.xml")
        Files.move(f,target)
        Files.createSymbolicLink(f,target)
        assertFalse(v.matches(expected))
        Files.delete(f)
        java.io.RandomAccessFile(f.toFile(),"rw").use{it.setLength(ManagedPreferenceDiskVerifier.MAX_BYTES.toLong()+1)}
        assertFalse(v.matches(expected))
    }

    @Test fun changedFileDuringVerificationIsRejected() = withFile { f ->
        write(f,xml)
        val verifier=ManagedPreferenceDiskVerifier(f){write(f,"<map/>")}
        assertFalse(verifier.matches(expected))
    }

    @Test fun evidenceIsCanonicalTypedAndAuthenticated() {
        val after=expected+("text" to "new")
        val k=key()
        val sealed=ManagedRecoveryEvidence.create(expected,after).seal(k)
        assertEquals(ManagedRecoveryEvidence.SEALED_SIZE,sealed.size)
        val proof=ManagedRecoveryEvidence.open(sealed,k)
        assertEquals(State.BEFORE,proof.classify(expected.toList().reversed().toMap()+("ids" to linkedSetOf("b","a"))))
        assertEquals(State.AFTER,proof.classify(after))
        assertEquals(State.UNKNOWN,proof.classify(expected+("port" to 443L)))
        assertEquals(State.UNKNOWN,proof.classify(expected+("text" to "partial")))
        invalid { ManagedRecoveryEvidence.open(sealed,key()) }
        val corrupt=sealed.copyOf();corrupt[corrupt.lastIndex]=(corrupt.last().toInt() xor 1).toByte()
        invalid { ManagedRecoveryEvidence.open(corrupt,k) }
        invalid { ManagedRecoveryEvidence.create(expected,expected) }
    }

    @Test fun realSyntheticFileTransactionAndCacheOnlySuccess() = withFile { f ->
        val old=mapOf<String,Any>("value" to "old")
        val after=mapOf<String,Any>("value" to "new")
        val patch=mapOf<String,Any?>("value" to "new")
        write(f,"<map><string name='value'>old</string></map>")
        val disk=ManagedPreferenceDiskVerifier(f)
        val gate=ManagedCrashGate(f.parent.resolve("gate"))
        val k=key()
        var actualWrite=true
        val backend=object:ManagedPreferenceBackend {
            var cache=old
            override fun read()=cache
            override fun commit(patch:Map<String,Any?>):Boolean {
                assertTrue(Files.exists(f.parent.resolve("gate/managed.pending")))
                cache=mapOf("value" to (patch["value"] ?: error("Unexpected removal")))
                if(actualWrite) write(f,"<map><string name='value'>"+cache["value"]+"</string></map>")
                return true
            }
        }
        val tx=ManagedCrashTransaction(gate,backend,{k},disk::matches)
        assertEquals(ManagedCrashTransaction.Outcome.APPLIED,tx.execute(old,patch){true})
        assertTrue(disk.matches(after))
        assertFalse(Files.exists(f.parent.resolve("gate/managed.pending")))
        actualWrite=false
        assertEquals(ManagedCrashTransaction.Outcome.RECOVERY_REQUIRED,
            tx.execute(after,mapOf("value" to "old")){true})
        assertTrue(disk.matches(after))
        assertEquals(State.BEFORE,gate.inspectPending { ManagedRecoveryEvidence.open(it,k).classify(disk.readVerified()) })
        assertEquals(ManagedCrashGate.Status.RECOVERY_REQUIRED,gate.acquire().status)
    }

    @Test fun recoveryConfirmationIsExplicitOneShotAndRechecksDiskAndMarker() = withFile { f ->
        write(f,xml)
        val gate=ManagedCrashGate(f.parent.resolve("gate"))
        val k=key()
        val after=expected+("text" to "new")
        fun marker()=ManagedRecoveryEvidence.create(expected,after).seal(k)
        gate.acquire().lease!!.use { assertTrue(it.beginMutation(marker())) }
        var now=1L
        val disk=ManagedPreferenceDiskVerifier(f)
        fun review()=ManagedRecoveryReview.prepare(gate,{k},disk::readVerified,{now}){true}!!
        val stale=review()
        write(f,xml.replace(" p&amp;雪 ","new"))
        assertFalse(stale.confirm(gate,{k},disk::readVerified){true})
        assertFalse(stale.confirm(gate,{k},disk::readVerified){true})
        val expired=review()
        now+=ManagedRecoveryReview.TTL_MS
        assertFalse(expired.confirm(gate,{k},disk::readVerified){true})
        val swapped=review()
        Files.write(f.parent.resolve("gate/managed.pending"),marker())
        assertFalse(swapped.confirm(gate,{k},disk::readVerified){true})
        val canceled=review();canceled.cancel()
        assertFalse(canceled.confirm(gate,{k},disk::readVerified){true})
        val approved=review()
        assertEquals(State.AFTER,approved.state)
        assertTrue(approved.confirm(gate,{k},disk::readVerified){true})
        assertFalse(Files.exists(f.parent.resolve("gate/managed.pending")))
        assertEquals(after,disk.readVerified())
        gate.acquire().lease!!.close()
    }

    @Test fun unknownOrUnauthenticatedStateCannotBeAcknowledged() = withFile { f ->
        write(f,xml.replace(" p&amp;雪 ","partial"))
        val gate=ManagedCrashGate(f.parent.resolve("gate"))
        val k=key()
        gate.acquire().lease!!.use {
            assertTrue(it.beginMutation(ManagedRecoveryEvidence.create(expected,expected+("text" to "new")).seal(k)))
        }
        val disk=ManagedPreferenceDiskVerifier(f)
        assertNull(ManagedRecoveryReview.prepare(gate,{k},disk::readVerified,{1L}){true})
        write(f,xml)
        assertNull(ManagedRecoveryReview.prepare(gate,{key()},disk::readVerified,{1L}){true})
        assertNull(ManagedRecoveryReview.prepare(gate,{k},disk::readVerified,{1L}){false})
        assertEquals(ManagedCrashGate.Status.RECOVERY_REQUIRED,gate.acquire().status)
    }

    @Test fun abandonedEvidenceInspectionNeverClearsMarker() = withFile { f ->
        write(f,xml)
        val gate=ManagedCrashGate(f.parent.resolve("gate"))
        val k=key()
        val after=expected+("text" to "new")
        gate.acquire().lease!!.use { assertTrue(it.beginMutation(ManagedRecoveryEvidence.create(expected,after).seal(k))) }
        assertEquals(State.BEFORE,gate.inspectPending { ManagedRecoveryEvidence.open(it,k).classify(ManagedPreferenceDiskVerifier(f).readVerified()) })
        assertEquals(ManagedCrashGate.Status.RECOVERY_REQUIRED,gate.acquire().status)
        assertEquals(State.UNKNOWN,gate.inspectPending { ManagedRecoveryEvidence.open(it,key()).classify(expected) })
        write(f,xml.replace(" p&amp;雪 ","new"))
        assertEquals(State.AFTER,gate.inspectPending { ManagedRecoveryEvidence.open(it,k).classify(ManagedPreferenceDiskVerifier(f).readVerified()) })
        assertEquals(ManagedCrashGate.Status.RECOVERY_REQUIRED,gate.acquire().status)
    }
}
