package ru.arvectum.proxylauncher.ui

import android.app.Activity
import ru.arvectum.proxylauncher.R
import ru.arvectum.proxylauncher.model.ImportedProxy
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.SavedSubscription
import ru.arvectum.proxylauncher.storage.*

/** Compile-time gate, no preference, remote flag or debug override. Activation needs separate acceptance. */
internal object ManagedSubscriptionActivation { const val ENABLED = false }

/** Main-thread coordinator. Every asynchronous result carries its original authenticated input and ticket. */
internal class ManagedSubscriptionController(
    activity:Activity, private val store:SecureProfileStore, private val catalog:SecureSubscriptionStore,
    private val selected:()->String?, private val allowed:()->Boolean, private val recoveryAllowed:()->Boolean,
    private val complete:(Int)->Unit,
) {
    private val dialogs=ManagedReviewDialogs(activity)
    internal class Request internal constructor(internal val ticket:ManagedReviewSession.Ticket,
        internal val input:SecureSubscriptionStore.ManagedFetchInput) {
        val url get()=input.url
        override fun toString()="ManagedSubscriptionRequest(redacted)"
    }
    fun update(foreground:Boolean,disconnected:Boolean,selectionIdentity:String?)=dialogs.update(foreground,disconnected,selectionIdentity)
    fun invalidate()=dialogs.invalidate()
    fun isCurrent(request:Request)=dialogs.permits(request.ticket)
    internal val activeDialog get()=dialogs.dialog
    fun beginFetch(source:SavedSubscription):Request? {
        val ticket=dialogs.begin() ?: return null
        val input=if(allowed()) catalog.managedFetchInput(source) else null
        if(input==null) { dialogs.invalidate();return null }
        return Request(ticket,input)
    }
    fun receive(request:Request,items:List<ImportedProxy>?) {
        val ticket=request.ticket
        if(!dialogs.permits(ticket) || !allowed()) return
        if(items==null) { dialogs.invalidate();complete(R.string.managed_unavailable);return }
        val review=store.prepareManagedRefresh(catalog,request.input,items,selected()) { allowed() && dialogs.permits(ticket) }
        if(review==null) { dialogs.invalidate();complete(R.string.managed_stale);return }
        showChange(ticket,review)
    }
    fun rollback(source:SavedSubscription) {
        val ticket=dialogs.begin() ?: return
        val review=store.prepareManagedRollback(catalog,source,selected()) { allowed() && dialogs.permits(ticket) }
        if(review==null) { dialogs.invalidate();complete(R.string.managed_stale);return }
        showChange(ticket,review)
    }
    private fun showChange(ticket:ManagedReviewSession.Ticket,review:ManagedChangeReview) {
        dialogs.change(ticket,review,{ consent ->
            store.confirmManagedChange(review,catalog,selected,{ allowed() && dialogs.permits(ticket) },consent)
        },complete)
    }
    fun remove(source:SavedSubscription) {
        val ticket=dialogs.begin() ?: return
        val review=store.prepareManagedOwnership(catalog,source,selected(),{ allowed() && dialogs.permits(ticket) })
        if(review==null) { dialogs.invalidate();complete(R.string.managed_stale);return }
        dialogs.ownership(ticket,review,{ consent ->
            store.confirmManagedOwnership(review,catalog,selected,{ allowed() && dialogs.permits(ticket) },consent)
        },complete)
    }
    fun edit(expected:ResolvedProxyProfile,edited:ProxyProfile,password:CharArray?):Boolean = ownedReview { permit ->
        store.prepareManagedProfileEdit(catalog,expected,edited,password,selected(),permit)
    }
    fun delete(expected:ResolvedProxyProfile):Boolean = ownedReview { permit ->
        store.prepareManagedProfileDelete(catalog,expected,selected(),permit)
    }
    private fun ownedReview(prepare:(()->Boolean)->ManagedOwnershipReview?):Boolean {
        val ticket=dialogs.begin() ?: return false
        val review=prepare { allowed() && dialogs.permits(ticket) }
        if(review==null) { dialogs.invalidate();complete(R.string.managed_stale);return false }
        return dialogs.ownership(ticket,review,{ consent ->
            store.confirmManagedOwnership(review,catalog,selected,{ allowed() && dialogs.permits(ticket) },consent)
        },complete)
    }
    fun recover() {
        val ticket=dialogs.begin() ?: return
        val review=store.prepareManagedRecoveryReview { recoveryAllowed() && dialogs.permits(ticket) }
        if(review==null) { dialogs.invalidate();complete(R.string.managed_recovery_required);return }
        dialogs.recovery(ticket,review,{ store.acknowledgeManagedRecovery(review) { recoveryAllowed() && dialogs.permits(ticket) } },complete)
    }
}
