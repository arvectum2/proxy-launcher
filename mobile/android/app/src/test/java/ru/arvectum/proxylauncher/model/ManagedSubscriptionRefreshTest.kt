package ru.arvectum.proxylauncher.model

import org.junit.Assert.*
import org.junit.Test

class ManagedSubscriptionRefreshTest {
    private val source = SavedSubscriptionCatalog.metadata("https://provider.example.com/list?token=fake",1)
    private val other = SavedSubscriptionCatalog.metadata("https://other.example.com/list",2)
    private val emptySelection = ManagedSelection(null,null,null,null,null,false)
    private fun row(id: String,host: String,owner: String? = null,password: String? = null,name: String = host) =
        ManagedProfileRow(ProxyProfile(id,name,host,80,ProxyType.HTTP,
            if(password!=null) "u" else null, password?.let { "android-keystore:$id" }),owner,password?.let { "cipher:$it" })
    private fun item(host: String,password: String?=null,name: String=host) =
        ImportedProxy(host,80,ProxyType.HTTP,if(password!=null)"u" else "",password.orEmpty(),name)
    private fun encrypt(id: String, item: ImportedProxy): String? =
        if(item.username.isNotEmpty()) "cipher:${item.password}" else null
    private fun prepare(items: List<ImportedProxy>,state: ManagedProfileState,clock: () -> Long = {1L}) =
        ManagedSubscriptionRefresh.prepare(source,items,state,clock,
            { r,p -> r.encryptedCredential == encrypt(r.profile.id,p) })

    @Test fun exactChangesAndInversePreserveForeignRows() {
        val manual=row("manual","manual.invalid",password="manual")
        val foreign=row("foreign","foreign.invalid",other.id)
        val old=row("owned","owned.invalid",source.id,"old")
        val missing=row("removed","remove.invalid",source.id)
        val state=ManagedProfileState(listOf(manual,foreign,old,missing),emptySelection)
        val plan=prepare(listOf(item("manual.invalid","changed"),item("foreign.invalid"),
            item("owned.invalid","new"),item("new.invalid")),state)!!
        assertEquals(2,plan.summary.skipped)
        assertEquals(setOf(ManagedSubscriptionRefresh.Kind.ADD,ManagedSubscriptionRefresh.Kind.UPDATE,
            ManagedSubscriptionRefresh.Kind.REMOVE),plan.summary.lines.map{it.kind}.toSet())
        val txn=plan.confirm(source,state,true,::encrypt)!!
        assertEquals(manual,txn.after.rows.single{it.profile.id=="manual"})
        assertEquals(foreign,txn.after.rows.single{it.profile.id=="foreign"})
        assertEquals("cipher:new",txn.after.rows.single{it.profile.id=="owned"}.encryptedCredential)
        assertFalse(txn.after.rows.any{it.profile.id=="removed"})
        assertEquals(source.id,txn.after.rows.single{it.profile.host=="new.invalid"}.owner)
        assertEquals(state,txn.rollback(source,txn.after,true))
        assertNull(plan.confirm(source,state,true,::encrypt))
        assertFalse(txn.toString().contains("cipher:"))
    }

    @Test fun neverAdoptsManualOrForeignAndNoDeletionOnlyCollision() {
        val state=ManagedProfileState(listOf(row("manual","a.invalid"),row("foreign","b.invalid",other.id)),emptySelection)
        val plan=prepare(listOf(item("a.invalid"),item("b.invalid")),state)!!
        assertTrue(plan.summary.lines.isEmpty())
        assertEquals(2,plan.summary.skipped)
        assertNull(plan.confirm(source,state,true,::encrypt))
        val withOwned=ManagedProfileState(state.rows+row("owned","c.invalid",source.id),emptySelection)
        assertNull(prepare(listOf(item("a.invalid"),item("b.invalid")),withOwned))
        assertNull(prepare(emptyList(),withOwned))
    }

    @Test fun protectsEverySelectionRole() {
        val owned=row("id","a.invalid",source.id,"old")
        for (selection in listOf(emptySelection.copy(active="id"),emptySelection.copy(primary="id"),
            emptySelection.copy(lastAuto="id"),emptySelection.copy(selected="id"),
            emptySelection.copy(recentlyFailed="id"))) {
            val state=ManagedProfileState(listOf(owned),selection)
            assertNull(prepare(listOf(item("a.invalid","new")),state))
            assertNull(prepare(listOf(item("b.invalid")),state))
            val unchanged=prepare(listOf(item("a.invalid","old")),state)!!
            assertEquals(1,unchanged.summary.unchanged)
        }
    }

    @Test fun staleOrExpiredApprovalNeverEncrypts() {
        val original=row("owned","a.invalid",source.id,"old")
        val state=ManagedProfileState(listOf(original),emptySelection)
        val input=listOf(item("a.invalid","new"))
        var now=1L
        fun plan()=prepare(input,state){now}!!
        fun reject(plan: ManagedSubscriptionRefresh, currentSource: SavedSubscription?,current: ManagedProfileState,fg:Boolean) {
            assertNull(plan.confirm(currentSource,current,fg){_,_->fail("Encryption before approval");null})
        }
        val expired=plan();now+=ManagedSubscriptionRefresh.TTL_MS
        reject(expired,source,state,true)
        reject(plan(),null,state,true)
        reject(plan(),other,state,true)
        reject(plan(),source,state,false)
        reject(plan(),source,ManagedProfileState(listOf(row("owned","a.invalid",source.id,"edited")),emptySelection),true)
        reject(plan(),source,ManagedProfileState(state.rows,emptySelection.copy(auto=true)),true)
        val canceled=plan();canceled.cancel();reject(canceled,source,state,true)
    }

    @Test fun rollbackRejectsAnyInterveningEditOrSelectionChange() {
        val state=ManagedProfileState(listOf(row("old","a.invalid",source.id,"old")),emptySelection)
        val txn=prepare(listOf(item("a.invalid","new")),state)!!.confirm(source,state,true,::encrypt)!!
        assertEquals(state,txn.rollback(source,txn.after,true))
        assertNull(txn.rollback(null,txn.after,true))
        assertNull(txn.rollback(source,txn.after,false))
        assertNull(txn.rollback(source,ManagedProfileState(txn.after.rows,emptySelection.copy(selected="old")),true))
        assertNull(txn.rollback(source,ManagedProfileState(txn.after.rows+row("manual","b.invalid"),emptySelection),true))
        assertNull(txn.rollback(source,state,true))
    }

    @Test fun conflictingDuplicateAndCorruptStateRejected() {
        val state=ManagedProfileState(emptyList(),emptySelection)
        assertNull(prepare(listOf(item("a.invalid","one"),item("A.invalid","two")),state))
        assertNull(prepare(listOf(item("a.invalid",name="first"),item("a.invalid",name="second")),state))
        val same=item("a.invalid")
        assertEquals(1,prepare(listOf(same,same),state)!!.summary.skipped)
        assertNull(prepare(List(201){same},state))
        val owned=row("owned","a.invalid",source.id)
        val collision=ManagedProfileState(listOf(owned,row("manual","a.invalid")),emptySelection)
        assertNull(prepare(listOf(same),collision))
        assertNull(prepare(listOf(same),ManagedProfileState(listOf(owned,owned),emptySelection)))
        assertNull(ManagedSubscriptionRefresh.prepare(source,listOf(same),collision,{1L},{_,_->false},{"owned"}))
    }

    @Test fun newIdCollisionAndCredentialFailureNeverProduceTransaction() {
        val state=ManagedProfileState(listOf(row("occupied","old.invalid")),emptySelection)
        assertNull(ManagedSubscriptionRefresh.prepare(source,listOf(item("new.invalid")),state,{1L},{_,_->false},{"occupied"}))
        val plan=prepare(listOf(item("new.invalid","secret")),state)!!
        assertNull(plan.confirm(source,state,true){_,_->null})
        assertEquals(1,state.rows.size)
    }
}
