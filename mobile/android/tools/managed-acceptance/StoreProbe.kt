package ru.arvectum.apl.acceptance

import android.app.Instrumentation
import android.os.Bundle
import ru.arvectum.proxylauncher.model.*
import ru.arvectum.proxylauncher.storage.*

/** Actual store adapters, only in the separate synthetic package, main-thread API. */
class StoreProbe:Instrumentation() {
    override fun onCreate(arguments:Bundle?) { super.onCreate(arguments);start() }
    override fun onStart() {
        val report=Bundle();var stage="init";var failure:Throwable?=null
        runOnMainSync {
            try {
                val c=targetContext
                check(c.packageName=="ru.arvectum.apl.acceptance")
                val store=SecureProfileStore(c);val catalog=SecureSubscriptionStore(c)
                val disk=ManagedPreferenceDiskVerifier(c.dataDir.toPath().resolve("shared_prefs/apl_mobile_profiles_v1.xml"))
                val catalogDisk=ManagedPreferenceDiskVerifier(c.dataDir.toPath().resolve("shared_prefs/apl_saved_subscriptions_v1.xml"))
                val applied=ManagedCrashTransaction.Outcome.APPLIED
                val stale=ManagedCrashTransaction.Outcome.STALE
                val url="https://example.com/synthetic-fixture"
                val source=catalog.add(url)
                val other=catalog.add("https://example.org/fixture")
                check(catalog.source(source)==url && catalog.managedFetchInput(source)?.url==url)
                check(catalogDisk.readVerified()==c.getSharedPreferences("apl_saved_subscriptions_v1",0).all)
                check(catalogDisk.readVerified().values.none { it.toString().contains(url) })
                report.putString("catalog_encryption","PASS")
                val anchor=ProxyProfile("anchor","A manual","anchor.invalid",8080,ProxyType.HTTP)
                store.saveProfile(anchor,null,false);store.setPrimaryProfileId(anchor.id)
                val first=ImportedProxy("managed.invalid",8081,ProxyType.HTTP,"fixture-user","fixture-old","Z managed")
                val updated=ImportedProxy(first.host,first.port,first.type,first.username,"fixture-new","Z updated")
                fun refresh(item:ImportedProxy)=store.prepareManagedRefresh(catalog,catalog.managedFetchInput(source)!!,listOf(item),null){true}!!
                fun confirm(review:ManagedChangeReview,consent:Boolean)=store.confirmManagedChange(review,catalog,{null},{true},consent)
                stage="initial_refresh"
                check(confirm(refresh(first),false)==applied)
                val owned=store.listProfiles().single { it.id!=anchor.id }
                check(store.loadProfile(owned.id)?.password==first.password)
                check(disk.readVerified()[ManagedPreferenceSchema.field(owned.id,"subscription_owner")]==source.id)
                check(disk.readVerified().values.none { it==first.password })
                check(store.getPrimaryProfileId()==anchor.id)
                report.putString("managed_import","PASS")
                stage="update"
                check(confirm(refresh(updated),false)==stale)
                check(store.loadProfile(owned.id)?.password==first.password)
                val review=refresh(updated);check(confirm(review,true)==applied);check(confirm(review,true)==stale)
                check(store.loadProfile(owned.id)?.password==updated.password)
                report.putString("reviewed_update","PASS")
                stage="rollback"
                val rollback=store.prepareManagedRollback(catalog,source,null){true}!!
                check(confirm(rollback,false)==applied);check(confirm(rollback,false)==stale)
                check(store.loadProfile(owned.id)?.password==first.password)
                check(ManagedPreferenceSchema.JOURNAL !in disk.readVerified())
                report.putString("reviewed_rollback","PASS")
                stage="ownership"
                check(runCatching { store.saveProfile(owned,null,false) }.isFailure)
                check(runCatching { store.deleteProfile(owned.id) }.isFailure)
                check(confirm(refresh(updated),false)==applied)
                fun removeReview()=store.prepareManagedOwnership(catalog,source,null,{true})!!
                check(removeReview().invalidatesRollback)
                check(store.confirmManagedOwnership(removeReview(),catalog,{null},{true},false)==stale)
                check(catalog.contains(source))
                check(store.confirmManagedOwnership(removeReview(),catalog,{null},{true},true)==applied)
                check(!catalog.contains(source) && catalog.contains(other))
                check(store.loadProfile(owned.id)?.password==updated.password)
                check(ManagedPreferenceSchema.field(owned.id,"subscription_owner") !in disk.readVerified())
                check(ManagedPreferenceSchema.JOURNAL !in disk.readVerified())
                check(store.getPrimaryProfileId()==anchor.id)
                report.putString("source_detach","PASS")
                stage="stale_catalog"
                val fetch=catalog.managedFetchInput(other)!!;catalog.add("https://example.net/fixture")
                check(store.prepareManagedRefresh(catalog,fetch,listOf(first),null){true}==null)
                report.putString("stale_catalog","PASS")
                stage="first_import_rollback"
                store.deleteProfile(owned.id);store.deleteProfile(anchor.id)
                val firstOther=store.prepareManagedRefresh(catalog,catalog.managedFetchInput(other)!!,listOf(first),null){true}!!
                check(confirm(firstOther,false)==applied)
                val id=store.listProfiles().single().id
                check(store.prepareManagedRollback(catalog,other,id){true}==null)
                check(confirm(store.prepareManagedRollback(catalog,other,null){true}!!,false)==applied)
                check(store.listProfiles().isEmpty())
                report.putString("first_import_rollback","PASS")
            } catch(t:Throwable) { failure=t }
        }
        val error=failure
        report.putString("result",if(error==null) "PASS" else "FAIL:$stage:${error.javaClass.simpleName}:${error.message?.take(160)}")
        finish(if(error==null) 0 else 1,report)
    }
}
