package ru.arvectum.proxylauncher.model

import org.junit.Assert.*
import org.junit.Test
import ru.arvectum.proxylauncher.storage.ManagedPreferenceBackend
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

    @Test fun newIdCannotOverwriteOrphan() {
        val raw=raw()+("profile.new.name" to "Orphan")
        val before=Schema.snapshot(raw,"manual")
        val row=ManagedProfileRow(ProxyProfile("new","New","new.invalid",80,ProxyType.HTTP),owner,null)
        reject { Schema.patch(raw,before,ManagedProfileState(before.rows+row,before.selection),owner,"journal") }
    }
}
