package ru.arvectum.apl.acceptance

import android.app.AlertDialog
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import ru.arvectum.proxylauncher.MainActivity
import ru.arvectum.proxylauncher.R
import ru.arvectum.proxylauncher.model.*
import ru.arvectum.proxylauncher.storage.*
import ru.arvectum.proxylauncher.ui.*

/** Actual coordinator with synthetic fetch results only. */
class ControllerProbe:Instrumentation() {
    override fun onCreate(arguments:Bundle?) { super.onCreate(arguments);start() }
    override fun onStart() {
        val report=Bundle();var stage="init";var failure:Throwable?=null;var activity:MainActivity?=null
        try {
            check(targetContext.packageName=="ru.arvectum.apl.acceptance")
            check(!ManagedSubscriptionActivation.ENABLED)
            val a=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            activity=a;waitForIdleSync()
            runOnMainSync {
                try {
                    val store=SecureProfileStore(a);val catalog=SecureSubscriptionStore(a)
                    val source=catalog.add("https://example.com/controller-fixture")
                    val anchor=ProxyProfile("anchor","A anchor","anchor.invalid",8080,ProxyType.HTTP)
                    store.saveProfile(anchor,null,false);store.setPrimaryProfileId(anchor.id)
                    val items=listOf(ImportedProxy("fixture.invalid",8081,ProxyType.HTTP,"fixture","synthetic","Z managed"))
                    val outcomes=mutableListOf<Int>()
                    val controller=ManagedSubscriptionController(a,store,catalog,{null},{true},{true},{outcomes.add(it)})
                    controller.update(true,true,null)
                    stage="selection"
                    val old=controller.beginFetch(source)!!
                    controller.update(true,true,"another");controller.update(true,true,null)
                    check(!controller.isCurrent(old));controller.receive(old,items)
                    check(controller.activeDialog==null && outcomes.isEmpty() && store.listProfiles().size==1)
                    report.putString("controller_stale_selection","PASS")
                    stage="catalog"
                    val catalogRequest=controller.beginFetch(source)!!
                    check(catalogRequest.url==catalog.source(source));check(!catalogRequest.toString().contains(catalogRequest.url))
                    catalog.add("https://example.org/other-fixture")
                    controller.receive(catalogRequest,items)
                    check(controller.activeDialog==null && outcomes.last()==R.string.managed_stale && store.listProfiles().size==1)
                    report.putString("controller_stale_catalog","PASS")
                    stage="explicit_confirmation"
                    val request=controller.beginFetch(source)!!;controller.receive(request,items)
                    val dialog=controller.activeDialog!!;check(store.listProfiles().size==1)
                    controller.receive(request,items);check(controller.activeDialog===dialog)
                    dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
                    check(outcomes.last()==R.string.managed_applied && store.listProfiles().size==2)
                    val count=outcomes.size;controller.receive(request,items)
                    check(outcomes.size==count && controller.activeDialog==null && store.listProfiles().size==2)
                    report.putString("controller_one_shot_fetch","PASS")
                    stage="connection"
                    val pending=controller.beginFetch(source)!!
                    controller.update(true,false,null);controller.update(true,true,null)
                    check(!controller.isCurrent(pending));controller.receive(pending,items)
                    check(controller.activeDialog==null && outcomes.size==count)
                    report.putString("controller_connection_roundtrip","PASS");controller.invalidate()
                    stage="owned_edit"
                    val owned=store.listProfiles().single { it.id!=anchor.id }
                    val oldProfile=store.loadProfile(owned.id)!!
                    val disk=ManagedPreferenceDiskVerifier(a.dataDir.toPath().resolve("shared_prefs/apl_mobile_profiles_v1.xml"))
                    val baseline=disk.readVerified()
                    fun edit()=store.prepareManagedProfileEdit(catalog,oldProfile,owned.copy(name="Z edited"),"replacement".toCharArray(),null){true}!!
                    val denied=edit();check(disk.matches(baseline));check(denied.invalidatesRollback)
                    check(store.confirmManagedOwnership(denied,catalog,{null},{true},false)==ManagedCrashTransaction.Outcome.STALE)
                    val edit=edit();check(store.confirmManagedOwnership(edit,catalog,{null},{true},true)==ManagedCrashTransaction.Outcome.APPLIED)
                    check(store.loadProfile(owned.id)?.password=="replacement");check(store.managedOwner(owned.id)==null)
                    check(store.getPrimaryProfileId()==anchor.id && catalog.contains(source))
                    check(store.prepareManagedProfileEdit(catalog,oldProfile,owned,"replacement".toCharArray(),null){true}==null)
                    report.putString("owned_credential_edit","PASS")
                    stage="owned_delete"
                    val newItems=listOf(ImportedProxy("delete-fixture.invalid",8082,ProxyType.HTTP,"fixture","delete-secret","Z delete"))
                    val fresh=store.prepareManagedRefresh(catalog,catalog.managedFetchInput(source)!!,newItems,null){true}!!
                    check(store.confirmManagedChange(fresh,catalog,{null},{true},false)==ManagedCrashTransaction.Outcome.APPLIED)
                    val victim=store.listProfiles().single { it.host=="delete-fixture.invalid" }
                    val victimExpected=store.loadProfile(victim.id)!!
                    check(store.prepareManagedProfileDelete(catalog,victimExpected,victim.id){true}==null)
                    val deletion=store.prepareManagedProfileDelete(catalog,victimExpected,null){true}!!
                    check(deletion.kind==ManagedOwnershipReview.Kind.MANUAL_DELETE && deletion.invalidatesRollback)
                    check(store.confirmManagedOwnership(deletion,catalog,{null},{true},true)==ManagedCrashTransaction.Outcome.APPLIED)
                    check(store.loadProfile(victim.id)==null && store.getPrimaryProfileId()==anchor.id && catalog.contains(source))
                    check(disk.readVerified().keys.none { it.startsWith("profile.${victim.id}.") || it=="secret.${victim.id}" })
                    report.putString("owned_delete","PASS")
                    stage="downgrade_guard"
                    check(store.additiveSourceRemovalAllowed(source))
                    val next=store.prepareManagedRefresh(catalog,catalog.managedFetchInput(source)!!,newItems,null){true}!!
                    check(store.confirmManagedChange(next,catalog,{null},{true},false)==ManagedCrashTransaction.Outcome.APPLIED)
                    check(!store.additiveSourceRemovalAllowed(source))
                    check(!store.additiveSourceRemovalAllowed(catalog.list().single { it.id!=source.id }))
                    val removal=store.prepareManagedOwnership(catalog,source,null,{true})!!
                    check(store.confirmManagedOwnership(removal,catalog,{null},{true},true)==ManagedCrashTransaction.Outcome.APPLIED)
                    check(store.additiveSourceRemovalAllowed(source));check(!catalog.contains(source))
                    report.putString("downgrade_guard","PASS")
                } catch(t:Throwable) { failure=t }
            }
        } catch(t:Throwable) { failure=t }
        finally { activity?.let { runCatching { runOnMainSync { it.finish() } } } }
        val error=failure;report.putString("result",if(error==null) "PASS" else "FAIL:$stage:${error.javaClass.simpleName}:${error.message?.take(160)}")
        finish(if(error==null) 0 else 1,report)
    }
}
