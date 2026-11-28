package ru.arvectum.apl.acceptance

import android.app.AlertDialog
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
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
                } catch(t:Throwable) { failure=t }
            }
        } catch(t:Throwable) { failure=t }
        finally { activity?.let { runCatching { runOnMainSync { it.finish() } } } }
        val error=failure;report.putString("result",if(error==null) "PASS" else "FAIL:$stage:${error.javaClass.simpleName}:${error.message?.take(160)}")
        finish(if(error==null) 0 else 1,report)
    }
}
