package ru.arvectum.proxylauncher.model

import org.junit.Assert.*
import org.junit.Test
import ru.arvectum.proxylauncher.storage.ManagedPreferenceBackend
import ru.arvectum.proxylauncher.storage.ManagedCrashGate
import ru.arvectum.proxylauncher.storage.ManagedCrashTransaction
import ru.arvectum.proxylauncher.storage.ManagedOwnershipReview
import ru.arvectum.proxylauncher.storage.ManagedChangeReview
import ru.arvectum.proxylauncher.storage.ManagedReviewSession
import ru.arvectum.proxylauncher.storage.ManagedOrdinaryWriteGuard
import java.nio.file.Files
import ru.arvectum.proxylauncher.storage.ManagedPreferenceSchema as Schema
import ru.arvectum.proxylauncher.storage.ManagedPreferenceTransaction
import ru.arvectum.proxylauncher.storage.ManagedPreferenceTransaction.Outcome

class ManagedPreferenceTransactionTest {
    private val source = SavedSubscriptionCatalog.metadata("https://supplier.example.com/list",1)
    private val owner = source.id
    private fun raw(): Map<String,Any> = mapOf(
        Schema.IDS to setOf("manual","owned"),
        "active_profile_id" to "manual", "pool_primary_profile_id" to "manual",
        "site_exclusions" to setOf("example.invalid"),
        "profile.manual.name" to "Manual", "profile.manual.host" to "manual.invalid",
        "profile.manual.port" to 80, "profile.manual.type" to "HTTP",
        "profile.owned.name" to "Owned", "profile.owned.host" to "owned.invalid",
        "profile.owned.port" to 80, "profile.owned.type" to "HTTP",
        "profile.owned.username" to "u", "profile.owned.password_ref" to "android-keystore:owned",
        "profile.owned.subscription_owner" to owner, "secret.owned" to "cipher-old",
        Schema.JOURNAL to "previous-encrypted-journal"
    )

    private class Fake(initial: Map<String,Any>, val behavior: (Int, MutableMap<String,Any>, Map<String,Any?>) -> Boolean) : ManagedPreferenceBackend {
        val values = initial.toMutableMap()
        var calls=0
        override fun read() = values.toMap()
        override fun commit(patch: Map<String,Any?>):Boolean {
            calls++
            return behavior(calls,values,patch)
        }
    }
    private fun apply(values: MutableMap<String,Any>, patch: Map<String,Any?>) {
        patch.forEach { (k,v) -> if(v==null) values.remove(k) else values[k]=v }
    }
    private fun patch(raw: Map<String,Any>): Map<String,Any?> {
        val before=Schema.snapshot(raw,"manual")
        val old=before.rows.single{it.profile.id=="owned"}
        val next=ManagedProfileState(before.rows.map {
            if(it.profile.id=="owned") ManagedProfileRow(old.profile.copy(name="New"),owner,"cipher-new") else it
        },before.selection)
        return Schema.patch(raw,before,next,owner,"encrypted-new-journal")
    }
    private fun reject(block:()->Unit) {
        try { block(); fail("Expected rejection") } catch (_:Exception) {}
    }

    @Test fun singleCommitAndReadbackPreserveUnrelatedKeys() {
        val raw=raw()
        val patch=patch(raw)
        val backend=Fake(raw){_,v,p->apply(v,p);true}
        assertEquals(Outcome.APPLIED,ManagedPreferenceTransaction(backend).execute(raw,patch){true})
        assertEquals(1,backend.calls)
        assertEquals("cipher-new",backend.values["secret.owned"])
        assertEquals("encrypted-new-journal",backend.values[Schema.JOURNAL])
        assertEquals(raw.filterKeys{it !in patch},backend.read().filterKeys{it !in patch})
        assertFalse(patch.keys.any{it.startsWith("profile.manual.") || it=="active_profile_id"})
    }

    @Test fun failedCommitWithPartialMutationRestoresPriorJournalAndProfile() {
        val raw=raw()
        val backend=Fake(raw){n,v,p->
            if(n==1){v["secret.owned"]="cipher-new";v[Schema.JOURNAL]="encrypted-new-journal";false}
            else {apply(v,p);true}
        }
        assertEquals(Outcome.RESTORED,ManagedPreferenceTransaction(backend).execute(raw,patch(raw)){true})
        assertEquals(raw,backend.read());assertEquals(2,backend.calls)
    }

    @Test fun trueCommitWithoutMatchingReadbackIsNotSuccess() {
        val raw=raw()
        val backend=Fake(raw){n,v,p-> if(n==1) true else {apply(v,p);true}}
        assertEquals(Outcome.RESTORED,ManagedPreferenceTransaction(backend).execute(raw,patch(raw)){true})
        assertEquals(raw,backend.read())
    }

    @Test fun failedRecoveryLatchesAndDoesNotRetry() {
        val raw=raw()
        val backend=Fake(raw){n,v,p->if(n==1)apply(v,p);false}
        val tx=ManagedPreferenceTransaction(backend)
        assertEquals(Outcome.RECOVERY_REQUIRED,tx.execute(raw,patch(raw)){true})
        assertEquals(Outcome.RECOVERY_REQUIRED,tx.execute(raw,patch(raw)){true})
        assertEquals(2,backend.calls)
    }

    @Test fun interveningChangeIsNeverOverwritten() {
        val raw=raw()
        val backend=Fake(raw){_,v,p->apply(v,p);v["site_exclusions"]=setOf("other.invalid");false}
        assertEquals(Outcome.RECOVERY_REQUIRED,ManagedPreferenceTransaction(backend).execute(raw,patch(raw)){true})
        assertEquals(setOf("other.invalid"),backend.values["site_exclusions"])
        assertEquals(1,backend.calls)
    }

    @Test fun staleOrClosedGateNeverWrites() {
        val raw=raw()
        val backend=Fake(raw){_,_,_->fail("Unexpected commit");false}
        val tx=ManagedPreferenceTransaction(backend)
        assertEquals(Outcome.STALE,tx.execute(raw,patch(raw)){false})
        backend.values["secret.owned"]="cipher-edit"
        assertEquals(Outcome.STALE,tx.execute(raw,patch(raw)){true})
        assertEquals(0,backend.calls)
    }

    @Test fun rejectsProtectedForeignOrCorruptRows() {
        val raw=raw()
        val before=Schema.snapshot(raw,"manual")
        val foreign=before.rows.single{it.profile.id=="manual"}
        val after=ManagedProfileState(before.rows.filter{it!=foreign},before.selection)
        reject { Schema.patch(raw,before,after,owner,"journal") }
        reject { Schema.snapshot(raw-"secret.owned","manual") }
        reject { Schema.snapshot(raw+("profile.owned.subscription_owner" to "invalid"),"manual") }
        reject { Schema.snapshot(raw-"profile.owned.name","manual") }
        val fallbackRaw=raw-"pool_primary_profile_id"
        val fallback=Schema.snapshot(fallbackRaw,"manual")
        val renamed=ManagedProfileState(fallback.rows.map {
            if(it.profile.id=="owned") ManagedProfileRow(it.profile.copy(name="A"),owner,it.encryptedCredential) else it
        },fallback.selection)
        reject { Schema.patch(fallbackRaw,fallback,renamed,owner,"journal") }
    }

    @Test fun sameCommitIncludesAddsRemovalsAndEncryptedRollback() {
        val raw=raw()
        val before=Schema.snapshot(raw,"manual")
        val owned=before.rows.single{it.profile.id=="owned"}
        val added=ManagedProfileRow(ProxyProfile("added","New","new.invalid",80,ProxyType.HTTP),owner,null)
        val after=ManagedProfileState(before.rows.filter{it!=owned}+added,before.selection)
        val key=javax.crypto.KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
        val journal=ManagedRollbackJournal.from(ManagedRefreshTransaction(source,before,after,setOf("owned","added"))).seal(key)
        val backend=Fake(raw){_,v,p->apply(v,p);true}
        val tx=ManagedPreferenceTransaction(backend)
        assertEquals(Outcome.APPLIED,tx.execute(raw,Schema.patch(raw,before,after,owner,journal)){true})
        val persisted=backend.read()
        assertEquals(after,Schema.snapshot(persisted,"manual"))
        assertFalse("secret.owned" in persisted)
        val restored=ManagedRollbackJournal.open(persisted[Schema.JOURNAL] as String,key).restore(source,after,true)!!
        assertEquals(before,restored)
        assertEquals(Outcome.APPLIED,tx.execute(persisted,Schema.patch(persisted,after,restored,owner,null)){true})
        assertEquals(raw-Schema.JOURNAL,backend.read())
        assertEquals(2,backend.calls)
    }

    @Test fun guardLostDuringWriteRequiresRecoveryWithoutUnsafeSecondCommit() {
        val raw=raw()
        var allowed=true
        val backend=Fake(raw){_,v,p->apply(v,p);allowed=false;true}
        val tx=ManagedPreferenceTransaction(backend)
        assertEquals(Outcome.RECOVERY_REQUIRED,tx.execute(raw,patch(raw)){allowed})
        assertEquals(1,backend.calls)
        assertEquals(Outcome.RECOVERY_REQUIRED,tx.execute(raw,patch(raw)){true})
        assertEquals(1,backend.calls)
    }

    @Test fun detachPreservesAllFieldsAndCredentialsAndDoesNotAdoptOnRefresh() {
        val raw=raw(); val before=Schema.snapshot(raw,"owned")
        val patch=Schema.detachPatch(raw,before,owner,"owned")
        assertEquals(setOf("profile.owned.subscription_owner",Schema.JOURNAL),patch.keys)
        val next=raw.toMutableMap();apply(next,patch)
        assertEquals(raw-patch.keys,next)
        val detached=Schema.snapshot(next,"owned")
        assertNull(detached.rows.single{it.profile.id=="owned"}.owner)
        val incoming=ImportedProxy(host="owned.invalid",port=80,type=ProxyType.HTTP,username="u",password="secret",name="Owned")
        val review=ManagedSubscriptionRefresh.prepare(source,listOf(incoming),detached,{1L},{_,_->false})!!
        assertEquals(1,review.summary.skipped)
        assertTrue(review.summary.lines.isEmpty())
    }

    @Test fun manualEditDetachesInSamePatchWithoutChangingSelection() {
        val raw=raw();val before=Schema.snapshot(raw,"owned")
        val edited=before.rows.single{it.profile.id=="owned"}.profile.copy(name="Manual edit")
        val patch=Schema.manualEditPatch(raw,before,owner,edited,"cipher-new")
        val backend=Fake(raw){_,v,p->apply(v,p);true}
        assertEquals(Outcome.APPLIED,ManagedPreferenceTransaction(backend).execute(raw,patch){true})
        val after=Schema.snapshot(backend.read(),"owned")
        assertEquals(1,backend.calls);assertEquals(before.selection,after.selection)
        assertEquals(ManagedProfileRow(edited,null,"cipher-new"),after.rows.single{it.profile.id=="owned"})
        assertFalse(Schema.JOURNAL in backend.values)
        assertEquals(before.rows.single{it.profile.id=="manual"},after.rows.single{it.profile.id=="manual"})
    }

    @Test fun detachRejectsWrongOwnerStaleAndForeignRow() {
        val raw=raw();val before=Schema.snapshot(raw,null)
        reject { Schema.detachPatch(raw,before,owner,"manual") }
        reject { Schema.detachPatch(raw,before,java.util.UUID.randomUUID().toString(),"owned") }
        reject { Schema.detachPatch(raw+("secret.owned" to "other"),before,owner) }
        val patch=Schema.detachPatch(raw,before,owner)
        val detached=raw.toMutableMap();apply(detached,patch)
        assertTrue(Schema.detachPatch(detached,Schema.snapshot(detached,null),owner).isEmpty())
    }

    @Test fun sourceDetachPreservesOtherOwnersAndRejectsOrphanOwnership() {
        val other=java.util.UUID.randomUUID().toString()
        val raw=raw()+("profile.manual.subscription_owner" to other)
        val before=Schema.snapshot(raw,null)
        val patch=Schema.detachPatch(raw,before,owner)
        assertEquals(setOf("profile.owned.subscription_owner",Schema.JOURNAL),patch.keys)
        val target=raw.toMutableMap();apply(target,patch)
        assertEquals(other,target["profile.manual.subscription_owner"])
        val orphan=raw+("profile.orphan.subscription_owner" to owner)
        reject { Schema.detachPatch(orphan,Schema.snapshot(orphan,null),owner) }
    }

    @Test fun detachFailureRestoresOwnershipAndJournal() {
        val raw=raw();val before=Schema.snapshot(raw,null)
        val patch=Schema.detachPatch(raw,before,owner)
        val backend=Fake(raw){n,v,p->apply(v,p);n>1}
        assertEquals(Outcome.RESTORED,ManagedPreferenceTransaction(backend).execute(raw,patch){true})
        assertEquals(raw,backend.read())
    }

    @Test fun authenticatedFirstImportRollbackCanRemoveOnlyImplicitPrimary() {
        val raw=mapOf<String,Any>(Schema.IDS to emptySet<String>(),"site_exclusions" to setOf("keep.invalid"))
        val empty=Schema.snapshot(raw,null)
        val added=ManagedProfileRow(ProxyProfile("new","New","new.invalid",80,ProxyType.HTTP),owner,null)
        val imported=ManagedProfileState(listOf(added),empty.selection)
        val key=javax.crypto.KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
        val sealed=ManagedRollbackJournal.from(ManagedRefreshTransaction(source,empty,imported,setOf("new"))).seal(key)
        val current=raw.toMutableMap();apply(current,Schema.patch(raw,empty,imported,owner,sealed))
        reject { Schema.patch(current,imported,empty,owner,null) }
        val patch=Schema.rollbackPatch(current,imported,source,key,true)!!
        assertNull(Schema.rollbackPatch(current,imported,source,key,false))
        assertNull(Schema.rollbackPatch(current,imported,source.copy(createdAt=source.createdAt+1),key,true))
        val selected=Schema.snapshot(current,"new")
        assertNull(Schema.rollbackPatch(current,selected,source,key,true))
        val auto=current+("auto_profile_selection" to true)
        assertNull(Schema.rollbackPatch(auto,Schema.snapshot(auto,null),source,key,true))
        assertNull(Schema.rollbackPatch(current-Schema.JOURNAL,imported,source,key,true))
        assertNull(Schema.rollbackPatch(current+(Schema.JOURNAL to "invalid"),imported,source,key,true))
        val wrongKey=javax.crypto.KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
        assertNull(Schema.rollbackPatch(current,imported,source,wrongKey,true))
        apply(current,patch);assertEquals(raw,current)
    }

    @Test fun rollbackCannotDropImplicitPrimaryWhenExistingProfilesRemain() {
        val raw=raw()-"active_profile_id"-"pool_primary_profile_id"
        val before=Schema.snapshot(raw,null)
        val new=ManagedProfileRow(ProxyProfile("new","A","new.invalid",80,ProxyType.HTTP),owner,null)
        val after=ManagedProfileState(before.rows+new,before.selection)
        val key=javax.crypto.KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
        val journal=ManagedRollbackJournal.from(ManagedRefreshTransaction(source,before,after,setOf("new"))).seal(key)
        val artificial=raw.toMutableMap();artificial[Schema.IDS]=setOf("manual","owned","new")
        artificial["profile.new.name"]="A";artificial["profile.new.host"]="new.invalid"
        artificial["profile.new.port"]=80;artificial["profile.new.type"]="HTTP";artificial["profile.new.subscription_owner"]=owner
        artificial[Schema.JOURNAL]=journal
        reject { Schema.rollbackPatch(artificial,after,source,key,true) }
    }

    private fun withOwnershipFixture(block:(Map<String,Any>,javax.crypto.SecretKey,ManagedCrashGate)->Unit) {
        val dir=Files.createTempDirectory("apl-ownership-")
        try {
            val key=javax.crypto.KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
            val raw=raw()-Schema.JOURNAL
            val before=Schema.snapshot(raw,null)
            val after=ManagedProfileState(before.rows.map { if(it.owner==owner) ManagedProfileRow(it.profile.copy(name="Updated"),owner,it.encryptedCredential) else it },before.selection)
            val journal=ManagedRollbackJournal.from(ManagedRefreshTransaction(source,before,after,setOf("owned"))).seal(key)
            val updated=raw.toMutableMap();apply(updated,Schema.patch(raw,before,after,owner,journal))
            block(updated,key,ManagedCrashGate(dir))
        } finally { dir.toFile().deleteRecursively() }
    }

    @Test fun reviewedSourceRemovalHoldsGateAndOnlyRunsAfterDurableDetach() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){_,v,p->apply(v,p);true}
        val tx=ManagedCrashTransaction(gate,backend,{key}){it==backend.read()}
        val review=ManagedOwnershipReview.prepare(source,"rev",raw,null,{1L},{key})!!
        assertEquals(1,review.detachedCount);assertTrue(review.invalidatesRollback)
        var calls=0
        val outcome=review.confirm(tx,{"rev"},{true},true){
            calls++;assertEquals(ManagedCrashGate.Status.BUSY,gate.acquire().status)
            assertFalse("profile.owned.subscription_owner" in backend.values)
            assertEquals(raw["secret.owned"],backend.values["secret.owned"]);true
        }
        assertEquals(ManagedCrashTransaction.Outcome.APPLIED,outcome);assertEquals(1,calls)
        assertEquals(ManagedCrashTransaction.Outcome.STALE,review.confirm(tx,{"rev"},{true},true){calls++;true})
        assertEquals(1,calls)
    }

    @Test fun catalogFailureNeverReattachesOrRetries() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){_,v,p->apply(v,p);true}
        val tx=ManagedCrashTransaction(gate,backend,{key}){it==backend.read()}
        val review=ManagedOwnershipReview.prepare(source,"rev",raw,null,{1L},{key})!!
        var calls=0
        assertEquals(ManagedCrashTransaction.Outcome.FOLLOWUP_UNCERTAIN,review.confirm(tx,{"rev"},{true},true){calls++;false})
        assertEquals(1,calls);assertEquals(1,backend.calls)
        assertNull(Schema.snapshot(backend.read(),null).rows.single{it.profile.id=="owned"}.owner)
        assertEquals(ManagedCrashTransaction.Outcome.STALE,review.confirm(tx,{"rev"},{true},true){calls++;true})
        assertEquals(1,calls)
    }

    @Test fun noCatalogCallOnFailedDetachOrUnknownDisk() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){n,v,p->apply(v,p);n>1}
        val tx=ManagedCrashTransaction(gate,backend,{key}){it==backend.read()}
        val review=ManagedOwnershipReview.prepare(source,"rev",raw,null,{1L},{key})!!
        assertEquals(ManagedCrashTransaction.Outcome.RESTORED,review.confirm(tx,{"rev"},{true},true){fail("catalog called");false})
        assertEquals(raw,backend.read())
        val bad=ManagedCrashTransaction(gate,backend,{key}){false}
        val next=ManagedOwnershipReview.prepare(source,"rev",raw,null,{1L},{key})!!
        assertEquals(ManagedCrashTransaction.Outcome.STALE,next.confirm(bad,{"rev"},{true},true){fail("catalog called");false})
    }

    @Test fun reviewRejectsExpiredChangedRevisionAndUnacceptedJournalLoss() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){_,_,_->fail("unexpected write");false}
        val tx=ManagedCrashTransaction(gate,backend,{key}){true}
        var now=1L
        fun review()=ManagedOwnershipReview.prepare(source,"rev",raw,null,{now},{key})!!
        assertEquals(ManagedCrashTransaction.Outcome.STALE,review().confirm(tx,{"rev"},{true},false){false})
        assertEquals(ManagedCrashTransaction.Outcome.STALE,review().confirm(tx,{"changed"},{true},true){false})
        val expired=review();now+=ManagedOwnershipReview.TTL_MS
        assertEquals(ManagedCrashTransaction.Outcome.STALE,expired.confirm(tx,{"rev"},{true},true){false})
        assertNull(ManagedOwnershipReview.prepare(source,"rev",raw+(Schema.JOURNAL to "bad"),null,{now},{key}))
        assertEquals(0,backend.calls)
    }

    @Test fun emptyDetachStillRequiresDurableStateAndExplicitReview() = withOwnershipFixture { raw,key,gate ->
        val detached=raw-Schema.JOURNAL-"profile.owned.subscription_owner"
        val backend=Fake(detached){_,_,_->fail("unexpected profile write");false}
        val tx=ManagedCrashTransaction(gate,backend,{key}){it==backend.read()}
        val review=ManagedOwnershipReview.prepare(source,"rev",detached,null,{1L},{key})!!
        assertEquals(0,review.detachedCount);assertFalse(review.invalidatesRollback)
        assertEquals(ManagedCrashTransaction.Outcome.APPLIED,review.confirm(tx,{"rev"},{true},false){
            assertEquals(ManagedCrashGate.Status.BUSY,gate.acquire().status);true})
        assertEquals(0,backend.calls)
    }

    @Test fun reviewedManualEditNeverCallsCatalogRemoval() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){_,v,p->apply(v,p);true}
        val tx=ManagedCrashTransaction(gate,backend,{key}){it==backend.read()}
        val edited=Schema.snapshot(raw,"owned").rows.single{it.profile.id=="owned"}.profile.copy(name="Manual")
        fun review()=ManagedOwnershipReview.prepare(source,"rev",raw,"owned",{1L},{key},edited,"cipher-new")!!
        assertEquals(ManagedCrashTransaction.Outcome.STALE,review().confirm(tx,{"rev"},{true},true){false})
        assertEquals(ManagedCrashTransaction.Outcome.APPLIED,review().confirm(tx,{"rev"},{true},true))
        assertEquals(ManagedProfileRow(edited,null,"cipher-new"),Schema.snapshot(backend.read(),"owned").rows.single{it.profile.id=="owned"})
    }

    @Test fun reviewedDeleteRemovesOnlyUnprotectedOwnedRow() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){_,v,p->apply(v,p);true}
        val tx=ManagedCrashTransaction(gate,backend,{key}){it==backend.read()}
        fun review()=ManagedOwnershipReview.prepare(source,"rev",raw,null,{1L},{key},deleteId="owned")!!
        assertNull(ManagedOwnershipReview.prepare(source,"rev",raw,"owned",{1L},{key},deleteId="owned"))
        assertNull(ManagedOwnershipReview.prepare(source,"rev",raw+("pool_primary_profile_id" to "owned"),null,{1L},{key},deleteId="owned"))
        assertEquals(ManagedCrashTransaction.Outcome.STALE,review().confirm(tx,{"rev"},{true},false))
        assertEquals(ManagedCrashTransaction.Outcome.APPLIED,review().confirm(tx,{"rev"},{true},true))
        assertEquals(setOf("manual"),backend.values[Schema.IDS]);assertFalse(backend.values.keys.any { it.startsWith("profile.owned.") || it=="secret.owned" })
        assertEquals(raw.filterKeys { !it.startsWith("profile.owned.") && it!="secret.owned" && it!=Schema.IDS && it!=Schema.JOURNAL },backend.values-Schema.IDS)
    }
    @Test fun manualEditCannotChangeImplicitPrimary() {
        val raw=raw()-"pool_primary_profile_id"
        val before=Schema.snapshot(raw,null)
        val edited=before.rows.single { it.profile.id=="owned" }.profile.copy(name="A first")
        reject { Schema.manualEditPatch(raw,before,owner,edited,"cipher-new") }
    }
    @Test fun emptySourceRemovalAuthenticatesAndInvalidatesOnlyItsJournal() = withOwnershipFixture { raw,key,gate ->
        val detached=raw-"profile.owned.subscription_owner"
        val backend=Fake(detached){_,v,p->apply(v,p);true}
        val tx=ManagedCrashTransaction(gate,backend,{key}){it==backend.read()}
        fun review()=ManagedOwnershipReview.prepare(source,"rev",detached,null,{1L},{key})!!
        assertEquals(0,review().detachedCount);assertTrue(review().invalidatesRollback)
        assertNull(ManagedOwnershipReview.prepare(source,"rev",detached+(Schema.JOURNAL to "bad"),null,{1L},{key}))
        val foreign=SavedSubscriptionCatalog.metadata("https://other.example.com/list",1)
        assertFalse(ManagedOwnershipReview.prepare(foreign,"rev",detached,null,{1L},{key})!!.invalidatesRollback)
        assertEquals(ManagedCrashTransaction.Outcome.STALE,review().confirm(tx,{"rev"},{true},false){fail("unexpected remove");false})
        assertEquals(ManagedCrashTransaction.Outcome.APPLIED,review().confirm(tx,{"rev"},{true},true){true})
        assertEquals(detached-Schema.JOURNAL,backend.read())
    }

    @Test fun ordinaryWritesRemainAvailableWhileVpnHoldsLeaseWithoutMarker() = withOwnershipFixture { _,_,gate ->
        val lease=gate.acquire().lease!!
        lease.use {
            assertEquals(7,ManagedOrdinaryWriteGuard.write(gate,{false}){7})
            assertEquals(ManagedCrashGate.Status.BUSY,gate.acquire().status)
        }
    }

    @Test fun ordinaryWritesAndConstructorCleanupBlockOnMarkerOrLatch() = withOwnershipFixture { _,_,gate ->
        var writes=0
        ManagedOrdinaryWriteGuard.ifAvailable(gate,{true}){writes++}
        reject { ManagedOrdinaryWriteGuard.write(gate,{true}){writes++} }
        gate.acquire().lease!!.use { assertTrue(it.beginMutation()) }
        assertFalse(gate.ordinaryWritesAllowed())
        ManagedOrdinaryWriteGuard.ifAvailable(gate,{false}){writes++}
        reject { ManagedOrdinaryWriteGuard.write(gate,{false}){writes++} }
        assertEquals(0,writes)
    }

    @Test fun ordinaryWriteWaitsForSameProcessMutationAndRechecksMarker() = withOwnershipFixture { _,_,gate ->
        val attempted=java.util.concurrent.CountDownLatch(1)
        val finished=java.util.concurrent.CountDownLatch(1)
        val allowed=java.util.concurrent.atomic.AtomicBoolean(true)
        val wrote=java.util.concurrent.atomic.AtomicBoolean(false)
        lateinit var worker:Thread
        synchronized(ManagedOrdinaryWriteGuard.monitor) {
            worker=Thread {
                attempted.countDown()
                allowed.set(runCatching { ManagedOrdinaryWriteGuard.write(gate,{false}){wrote.set(true)} }.isSuccess)
                finished.countDown()
            }.apply { start() }
            assertTrue(attempted.await(2,java.util.concurrent.TimeUnit.SECONDS))
            gate.acquire().lease!!.use { assertTrue(it.beginMutation()) }
            assertFalse(finished.await(50,java.util.concurrent.TimeUnit.MILLISECONDS))
        }
        worker.join(2000)
        assertFalse(worker.isAlive);assertFalse(allowed.get());assertFalse(wrote.get())
    }

    @Test fun markerProbeDoesNotCreateFilesAndRejectsAmbiguousDirectory() {
        val root=Files.createTempDirectory("apl-ordinary-")
        try {
            val path=root.resolve("gate")
            val gate=ManagedCrashGate(path)
            assertTrue(gate.ordinaryWritesAllowed());assertFalse(Files.exists(path))
            Files.write(path,byteArrayOf(1));assertFalse(gate.ordinaryWritesAllowed())
            Files.delete(path);Files.createSymbolicLink(path,root.resolve("missing"))
            assertFalse(gate.ordinaryWritesAllowed())
        } finally { root.toFile().deleteRecursively() }
    }

    @Test fun rollbackReviewIsExactOneShotAndShowsOnlyEndpoint() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){_,v,p->apply(v,p);true}
        val tx=ManagedCrashTransaction(gate,backend,{key}){it==backend.read()}
        val review=ManagedChangeReview.rollback(source,"rev",raw,null,{1L},key){}!!
        assertEquals(ManagedChangeReview.Kind.ROLLBACK,review.kind)
        assertEquals(listOf(ManagedSubscriptionRefresh.Line(ManagedSubscriptionRefresh.Kind.UPDATE,ProxyType.HTTP,"owned.invalid",80)),review.lines)
        assertFalse(review.toString().contains("cipher"))
        assertEquals(ManagedCrashTransaction.Outcome.APPLIED,review.confirm(tx,backend::read,{"rev"},{null},{true},false))
        assertEquals("Owned",backend.values["profile.owned.name"])
        assertFalse(Schema.JOURNAL in backend.values)
        assertEquals(ManagedCrashTransaction.Outcome.STALE,review.confirm(tx,backend::read,{"rev"},{null},{true},false))
        assertEquals(1,backend.calls)
    }

    @Test fun rollbackReviewRejectsExpiredCancelledStaleSelectionCatalogAndJournal() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){_,_,_->fail("unexpected write");false}
        val tx=ManagedCrashTransaction(gate,backend,{key}){true}
        var now=1L
        fun review()=ManagedChangeReview.rollback(source,"rev",raw,null,{now},key){}!!
        fun confirm(r:ManagedChangeReview, revision:String="rev",selected:String?=null,allowed:Boolean=true)=
            r.confirm(tx,backend::read,{revision},{selected},{allowed},false)
        assertEquals(ManagedCrashTransaction.Outcome.STALE,confirm(review(),revision="changed"))
        assertEquals(ManagedCrashTransaction.Outcome.STALE,confirm(review(),selected="manual"))
        assertEquals(ManagedCrashTransaction.Outcome.STALE,confirm(review(),allowed=false))
        val cancelled=review();cancelled.cancel();assertEquals(ManagedCrashTransaction.Outcome.STALE,confirm(cancelled))
        val expired=review();now+=ManagedChangeReview.TTL_MS;assertEquals(ManagedCrashTransaction.Outcome.STALE,confirm(expired))
        val changed=review();backend.values["site_exclusions"]=setOf("different.invalid")
        assertEquals(ManagedCrashTransaction.Outcome.STALE,confirm(changed))
        assertNull(ManagedChangeReview.rollback(source,"rev",raw+(Schema.JOURNAL to "corrupt"),null,{now},key){})
        assertEquals(0,backend.calls)
    }

    @Test fun refreshReviewRequiresReplacementConsentAndExactRawBeforeBuilding() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){_,v,p->apply(v,p);true}
        val tx=ManagedCrashTransaction(gate,backend,{key}){it==backend.read()}
        var builds=0
        fun review():ManagedChangeReview {
            val before=Schema.snapshot(raw,null)
            val incoming=ImportedProxy("owned.invalid",80,ProxyType.HTTP,"u","password","New")
            val plan=ManagedSubscriptionRefresh.prepare(source,listOf(incoming),before,{1L},{_,_->false})!!
            return ManagedChangeReview.refresh(source,"rev",raw,null,plan,{1L},
                { ManagedRollbackJournal.open(raw[Schema.JOURNAL] as String,key) }) { approved,expected ->
                builds++
                val state=Schema.snapshot(expected,null)
                val txn=approved.confirm(source,state,true){_,_->"cipher-new"}!!
                Schema.patch(expected,state,txn.after,source.id,ManagedRollbackJournal.from(txn).seal(key))
            }!!
        }
        val rejected=review();assertTrue(rejected.replacesRollback)
        assertEquals(ManagedCrashTransaction.Outcome.STALE,rejected.confirm(tx,backend::read,{"rev"},{null},{true},false))
        assertEquals(0,builds)
        val stale=review();backend.values["site_exclusions"]=setOf("changed.invalid")
        assertEquals(ManagedCrashTransaction.Outcome.STALE,stale.confirm(tx,backend::read,{"rev"},{null},{true},true))
        assertEquals(0,builds)
        backend.values["site_exclusions"]=raw.getValue("site_exclusions")
        val approved=review()
        assertEquals(ManagedCrashTransaction.Outcome.APPLIED,approved.confirm(tx,backend::read,{"rev"},{null},{true},true))
        assertEquals(1,builds);assertEquals("cipher-new",backend.values["secret.owned"])
        assertEquals(ManagedCrashTransaction.Outcome.STALE,approved.confirm(tx,backend::read,{"rev"},{null},{true},true))
        assertEquals(1,builds)
    }

    @Test fun rollbackReviewRechecksCredentialAndFailsBeforeWrite() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){_,_,_->fail("unexpected write");false}
        val tx=ManagedCrashTransaction(gate,backend,{key}){true}
        var available=true
        val review=ManagedChangeReview.rollback(source,"rev",raw,null,{1L},key){check(available)}!!
        available=false
        assertEquals(ManagedCrashTransaction.Outcome.STALE,review.confirm(tx,backend::read,{"rev"},{null},{true},false))
        assertEquals(0,backend.calls)
    }

    @Test fun patchPreparationRequiresLeaseAndDurableBaseline() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){_,v,p->apply(v,p);true}
        var builds=0
        val tx=ManagedCrashTransaction(gate,backend,{key}){it==backend.read()}
        val lease=gate.acquire().lease!!
        lease.use {
            assertEquals(ManagedCrashTransaction.Outcome.BUSY,tx.executePrepared(raw,{true}){builds++;emptyMap()})
        }
        assertEquals(0,builds)
        assertEquals(ManagedCrashTransaction.Outcome.APPLIED,tx.executePrepared(raw,{true}){
            builds++;assertEquals(ManagedCrashGate.Status.BUSY,gate.acquire().status)
            mapOf("site_exclusions" to setOf("other.invalid"))
        })
        assertEquals(1,builds)
        assertEquals(ManagedCrashTransaction.Outcome.STALE,tx.executePrepared(raw,{true}){builds++;emptyMap()})
        assertEquals(1,builds)
    }

    @Test fun patchPreparationRechecksPermissionBeforeWriting() = withOwnershipFixture { raw,key,gate ->
        val backend=Fake(raw){_,_,_->fail("unexpected write");false}
        val tx=ManagedCrashTransaction(gate,backend,{key}){true}
        var allowed=true
        assertEquals(ManagedCrashTransaction.Outcome.STALE,tx.executePrepared(raw,{allowed}){
            allowed=false;mapOf("site_exclusions" to emptySet<String>())
        })
        assertEquals(0,backend.calls);assertTrue(gate.ordinaryWritesAllowed())
    }

    @Test fun previewRejectsChangingImplicitPrimaryAndOrphanId() = withOwnershipFixture { raw,key,_ ->
        val withoutPrimary=raw-"active_profile_id"-"pool_primary_profile_id"
        val state=Schema.snapshot(withoutPrimary,null)
        val early=ImportedProxy("new.invalid",80,ProxyType.HTTP,"","","A")
        val keep=ImportedProxy("owned.invalid",80,ProxyType.HTTP,"u","password","Updated")
        val plan=ManagedSubscriptionRefresh.prepare(source,listOf(early,keep),state,{1L},{_,_->true},{"new"})!!
        assertFalse(Schema.validateRefreshPreview(withoutPrimary,state,plan.projection(state)!!))
        val explicit=Schema.snapshot(raw,null)
        val orphan=raw+("profile.new.name" to "Orphan")
        val second=ManagedSubscriptionRefresh.prepare(source,listOf(early,keep),explicit,{1L},{_,_->true},{"new"})!!
        assertTrue(Schema.validateRefreshPreview(raw,explicit,second.projection(explicit)!!))
        assertFalse(Schema.validateRefreshPreview(orphan,explicit,second.projection(explicit)!!))
    }

    @Test fun lifecycleSessionDiscardsStaleFetchAndCancelsOnRoundTrip() {
        val session=ManagedReviewSession();var cancelled=0
        assertNull(session.begin())
        session.update(true,true,"a");val first=session.begin()!!
        assertTrue(session.attach(first){cancelled++})
        session.update(false,true,"a");session.update(true,true,"a")
        assertFalse(session.permits(first));assertEquals(1,cancelled)
        val second=session.begin()!!
        assertFalse(session.attach(first){cancelled++});assertTrue(session.permits(second))
        assertTrue(session.attach(second){cancelled++})
        session.update(true,false,"a");session.update(true,true,"a")
        assertFalse(session.permits(second));assertEquals(3,cancelled)
        val third=session.begin()!!;session.update(true,true,"b");session.update(true,true,"a")
        assertFalse(session.permits(third))
    }

    @Test fun newIdCannotOverwriteOrphan() {
        val raw=raw()+("profile.new.name" to "Orphan")
        val before=Schema.snapshot(raw,"manual")
        val row=ManagedProfileRow(ProxyProfile("new","New","new.invalid",80,ProxyType.HTTP),owner,null)
        reject { Schema.patch(raw,before,ManagedProfileState(before.rows+row,before.selection),owner,"journal") }
    }
}
