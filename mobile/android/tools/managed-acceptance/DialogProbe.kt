package ru.arvectum.apl.acceptance

import android.app.AlertDialog
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import java.security.KeyStore
import javax.crypto.SecretKey
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import ru.arvectum.proxylauncher.MainActivity
import ru.arvectum.proxylauncher.R
import ru.arvectum.proxylauncher.model.*
import ru.arvectum.proxylauncher.storage.*

/** Real dialogs and store, no network or production activity. */
class DialogProbe:Instrumentation() {
    override fun onCreate(arguments:Bundle?) { super.onCreate(arguments);start() }
    override fun onStart() {
        val report=Bundle();var stage="init";var activity:MainActivity?=null;var failure:Throwable?=null
        var backgroundTicket:ManagedReviewSession.Ticket?=null
        try {
            check(targetContext.packageName=="ru.arvectum.apl.acceptance")
            val a=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            activity=a;waitForIdleSync()
            runOnMainSync {
                try {
                    val store=SecureProfileStore(a);val catalog=SecureSubscriptionStore(a)
                    val source=catalog.add("https://example.com/dialog-fixture")
                    val anchor=ProxyProfile("ui-anchor","A anchor","anchor.invalid",8080,ProxyType.HTTP)
                    store.saveProfile(anchor,null,false);store.setPrimaryProfileId(anchor.id)
                    val item=ImportedProxy("managed.invalid",8081,ProxyType.HTTP,"fixture","old-fixture","Z managed")
                    val updated=ImportedProxy(item.host,item.port,item.type,item.username,"new-fixture","Z updated")
                    val ui=a.reviews
                    fun prepare(i:ImportedProxy)=store.prepareManagedRefresh(catalog,catalog.managedFetchInput(source)!!,listOf(i),null){true}!!
                    var calls=0;var message=0
                    fun display(i:ImportedProxy):ManagedReviewSession.Ticket {
                        val t=ui.begin()!!;val review=prepare(i)
                        check(ui.change(t,review,{ consent -> calls++;store.confirmManagedChange(review,catalog,{null},{ui.permits(t)},consent) },{message=it}))
                        return t
                    }
                    fun positive()=ui.dialog!!.getButton(AlertDialog.BUTTON_POSITIVE)
                    fun checkbox(v:View):CheckBox? = if(v is CheckBox) v else if(v is ViewGroup) (0 until v.childCount).firstNotNullOfOrNull { checkbox(v.getChildAt(it)) } else null
                    stage="apply"
                    display(item);check(positive().isEnabled);positive().performClick();check(calls==1 && message==R.string.managed_applied)
                    check(ui.dialog==null);report.putString("dialog_explicit_apply","PASS")
                    stage="consent"
                    display(updated);check(!positive().isEnabled)
                    val consent=checkbox(ui.dialog!!.window!!.decorView)!!;consent.isChecked=true;check(positive().isEnabled)
                    positive().performClick();check(calls==2 && message==R.string.managed_applied)
                    report.putString("dialog_replacement_consent","PASS")
                    stage="selection"
                    val ticket=display(item);ui.update(true,true,"other");ui.update(true,true,null)
                    check(!ui.permits(ticket) && ui.dialog==null && calls==2)
                    report.putString("dialog_selection_invalidation","PASS")
                    stage="pause"
                    val t=display(item);callActivityOnPause(a);check(!ui.permits(t) && ui.dialog==null && calls==2)
                    callActivityOnResume(a);check(!ui.permits(t));report.putString("dialog_lifecycle_invalidation","PASS")
                    stage="rollback"
                    val rt=ui.begin()!!;val rollback=store.prepareManagedRollback(catalog,source,null){true}!!
                    check(ui.change(rt,rollback,{ consent -> calls++;store.confirmManagedChange(rollback,catalog,{null},{ui.permits(rt)},consent) },{message=it}))
                    check(positive().isEnabled);positive().performClick();check(calls==3 && message==R.string.managed_applied)
                    val owned=store.listProfiles().single { it.id!=anchor.id };check(store.loadProfile(owned.id)?.password==item.password)
                    report.putString("dialog_rollback","PASS")
                    stage="detach"
                    val dt=ui.begin()!!;val detach=store.prepareManagedOwnership(catalog,source,null,{true})!!
                    check(ui.ownership(dt,detach,{ consent -> calls++;store.confirmManagedOwnership(detach,catalog,{null},{ui.permits(dt)},consent) },{message=it}))
                    check(positive().isEnabled);positive().performClick();check(calls==4 && message==R.string.managed_applied)
                    check(!catalog.contains(source));check(store.loadProfile(owned.id)?.password==item.password)
                    report.putString("dialog_detach","PASS")
                    stage="stale_fetch"
                    val old=ui.begin()!!;ui.update(true,false,null);ui.update(true,true,null)
                    val fresh=ui.begin()!!;check(!ui.permits(old) && ui.permits(fresh));ui.invalidate()
                    report.putString("dialog_stale_fetch","PASS")
                    stage="manual_edit"
                    val source2=catalog.add("https://example.org/second-fixture")
                    val second=ImportedProxy("editable.invalid",8181,ProxyType.HTTP,"fixture","edit-fixture","Z editable")
                    val initial=store.prepareManagedRefresh(catalog,catalog.managedFetchInput(source2)!!,listOf(second),null){true}!!
                    check(store.confirmManagedChange(initial,catalog,{null},{true},false)==ManagedCrashTransaction.Outcome.APPLIED)
                    val row=store.listProfiles().single { it.host==second.host }
                    val disk=ManagedPreferenceDiskVerifier(a.dataDir.toPath().resolve("shared_prefs/apl_mobile_profiles_v1.xml"))
                    val raw=disk.readVerified()
                    val encrypted=raw[ManagedPreferenceSchema.secret(row.id)] as String
                    val revised=row.copy(name="Z manually edited")
                    val edit=store.prepareManagedOwnership(catalog,source2,null,{true},revised,encrypted)!!
                    val et=ui.begin()!!
                    check(ui.ownership(et,edit,{ consent -> calls++;store.confirmManagedOwnership(edit,catalog,{null},{ui.permits(et)},consent) },{message=it}))
                    check(!positive().isEnabled);checkbox(ui.dialog!!.window!!.decorView)!!.isChecked=true
                    positive().performClick();check(calls==5 && message==R.string.managed_applied)
                    check(store.loadProfile(row.id)?.profile==revised && store.loadProfile(row.id)?.password==second.password)
                    check(ManagedPreferenceSchema.field(row.id,"subscription_owner") !in disk.readVerified());check(catalog.contains(source2))
                    report.putString("dialog_manual_edit","PASS")
                    stage="recovery"
                    val baseline=disk.readVerified()
                    val ks=KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                    val evidenceKey=ks.getKey("ru.arvectum.proxylauncher.managed_evidence.v1",null) as SecretKey
                    val gate=managedProfileGate(a)
                    gate.acquire().lease!!.use { check(it.beginMutation(ManagedRecoveryEvidence.create(baseline,baseline+("site_exclusions" to setOf("fixture.invalid"))).seal(evidenceKey))) }
                    check(runCatching { store.setSiteExclusions(setOf("fixture.invalid")) }.isFailure)
                    val recovery=store.prepareManagedRecoveryReview{true}!!;check(recovery.state==ManagedRecoveryEvidence.State.BEFORE)
                    val recTicket=ui.begin()!!
                    check(ui.recovery(recTicket,recovery,{ calls++;store.acknowledgeManagedRecovery(recovery){ui.permits(recTicket)} },{message=it}))
                    positive().performClick();check(calls==6 && message==R.string.managed_applied)
                    check(disk.matches(baseline));check(gate.ordinaryWritesAllowed())
                    report.putString("dialog_recovery_ack","PASS")
                    stage="os_background"
                    val newItem=ImportedProxy("background.invalid",8191,ProxyType.HTTP,"","","Z background")
                    val bgReview=store.prepareManagedRefresh(catalog,catalog.managedFetchInput(source2)!!,listOf(newItem),null){true}!!
                    val bgTicket=ui.begin()!!;backgroundTicket=bgTicket
                    check(ui.change(bgTicket,bgReview,{ calls++;error("unexpected background confirmation") },{message=it}))
                    check(a.moveTaskToBack(true))
                } catch(t:Throwable) { failure=t }
            }
            if(failure==null) {
                val deadline=SystemClock.elapsedRealtime()+8000
                var paused=false
                while(!paused && SystemClock.elapsedRealtime()<deadline) {
                    Thread.sleep(50);runOnMainSync { paused=!a.resumed }
                }
                check(paused)
                runOnMainSync {
                    check(!a.reviews.permits(backgroundTicket!!) && a.reviews.dialog==null)
                    a.startActivity(Intent(a,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
                }
                val resumeDeadline=SystemClock.elapsedRealtime()+8000
                var resumed=false
                while(!resumed && SystemClock.elapsedRealtime()<resumeDeadline) {
                    Thread.sleep(50);runOnMainSync { resumed=a.resumed }
                }
                check(resumed)
                runOnMainSync { check(!a.reviews.permits(backgroundTicket!!) && a.reviews.dialog==null) }
                report.putString("dialog_os_background","PASS")
            }
        } catch(t:Throwable) { failure=t }
        finally { activity?.let { runCatching { runOnMainSync { it.finish() } } } }
        val error=failure;report.putString("result",if(error==null) "PASS" else "FAIL:$stage:${error.javaClass.simpleName}:${error.message?.take(160)}")
        finish(if(error==null) 0 else 1,report)
    }
}
