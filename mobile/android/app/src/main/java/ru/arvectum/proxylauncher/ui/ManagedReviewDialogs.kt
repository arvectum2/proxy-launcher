package ru.arvectum.proxylauncher.ui

import android.app.Activity
import android.app.AlertDialog
import android.os.Looper
import android.view.WindowManager
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import ru.arvectum.proxylauncher.R
import ru.arvectum.proxylauncher.model.ManagedSubscriptionRefresh
import ru.arvectum.proxylauncher.storage.*

/** Offline candidate UI. No entry point from the production activity until release gates pass.
 * The caller must supply actual lifecycle/selection state via update and invalidate before navigation.
 * Only an explicit positive-button click can call the store confirmation adapter.
 */
internal class ManagedReviewDialogs(private val activity: Activity) {
    private val session=ManagedReviewSession()
    internal var dialog: AlertDialog?=null
        private set
    private fun main()=check(Looper.myLooper()==Looper.getMainLooper())
    fun update(foreground:Boolean, disconnected:Boolean, selected:String?) {
        main();session.update(foreground,disconnected,selected)
    }
    fun begin():ManagedReviewSession.Ticket? { main();return session.begin() }
    fun permits(ticket:ManagedReviewSession.Ticket):Boolean { main();return session.permits(ticket) }
    fun invalidate() { main();session.invalidate() }

    fun change(ticket:ManagedReviewSession.Ticket,review:ManagedChangeReview,
               confirm:(Boolean)->ManagedCrashTransaction.Outcome, complete:(Int)->Unit):Boolean {
        val title=if(review.kind==ManagedChangeReview.Kind.REFRESH) R.string.managed_refresh_title else R.string.managed_rollback_title
        val body=buildString {
            append(activity.getString(R.string.managed_review_notice))
            review.lines.forEach { line ->
                val action=when(line.kind) {
                    ManagedSubscriptionRefresh.Kind.ADD -> R.string.managed_add
                    ManagedSubscriptionRefresh.Kind.UPDATE -> R.string.managed_update
                    ManagedSubscriptionRefresh.Kind.REMOVE -> R.string.managed_remove
                }
                val host=line.host.filter { !it.isISOControl() && Character.getType(it)!=Character.FORMAT.toInt() }.take(253)
                val endpoint=if(':' in host) "[$host]" else host
                append("\n\n").append(activity.getString(action)).append(" · ").append(line.type.name)
                    .append(" · ").append(endpoint).append(':').append(line.port)
            }
        }
        return show(ticket,title,body,review.replacesRollback,review::cancel,confirm,complete)
    }

    fun ownership(ticket:ManagedReviewSession.Ticket,review:ManagedOwnershipReview,
                  confirm:(Boolean)->ManagedCrashTransaction.Outcome,complete:(Int)->Unit):Boolean {
        val title=when(review.kind) {
            ManagedOwnershipReview.Kind.REMOVE_SOURCE -> R.string.managed_detach_title
            ManagedOwnershipReview.Kind.MANUAL_EDIT -> R.string.managed_edit_title
            ManagedOwnershipReview.Kind.MANUAL_DELETE -> R.string.managed_remove
        }
        val body=when(review.kind) {
            ManagedOwnershipReview.Kind.REMOVE_SOURCE -> activity.getString(R.string.managed_detach_notice,review.detachedCount)
            ManagedOwnershipReview.Kind.MANUAL_EDIT -> activity.getString(R.string.managed_edit_notice)
            ManagedOwnershipReview.Kind.MANUAL_DELETE -> activity.getString(R.string.managed_review_notice)
        }
        val target=review.targetProfile?.let { p ->
            val name=p.name.filter { !it.isISOControl() && Character.getType(it)!=Character.FORMAT.toInt() }.take(160)
            val host=p.host.filter { !it.isISOControl() && Character.getType(it)!=Character.FORMAT.toInt() }.take(253)
            val endpoint=if(':' in host) "[$host]" else host
            "\n\n$name · ${p.type.name} · $endpoint:${p.port}"
        }.orEmpty()
        return show(ticket,title,body+target,review.invalidatesRollback,review::cancel,confirm,complete)
    }

    fun recovery(ticket:ManagedReviewSession.Ticket,review:ManagedRecoveryReview,
                 confirm:()->Boolean,complete:(Int)->Unit):Boolean {
        val body=when(review.state) {
            ManagedRecoveryEvidence.State.BEFORE -> R.string.managed_recovery_before
            ManagedRecoveryEvidence.State.AFTER -> R.string.managed_recovery_after
            ManagedRecoveryEvidence.State.UNKNOWN -> { review.cancel();return false }
        }
        return show(ticket,R.string.managed_recovery_title,activity.getString(body),false,review::cancel,
            { if(confirm()) ManagedCrashTransaction.Outcome.APPLIED else ManagedCrashTransaction.Outcome.RECOVERY_REQUIRED },complete)
    }

    private fun show(ticket:ManagedReviewSession.Ticket,title:Int,body:String,needsConsent:Boolean,cancel:()->Unit,
                     confirm:(Boolean)->ManagedCrashTransaction.Outcome,complete:(Int)->Unit):Boolean {
        main()
        if(activity.isFinishing || activity.isDestroyed || !session.permits(ticket)) { cancel();return false }
        val padding=(20*activity.resources.displayMetrics.density).toInt()
        val content=LinearLayout(activity).apply { orientation=LinearLayout.VERTICAL;setPadding(padding,padding,padding,padding) }
        content.addView(TextView(activity).apply { text=body;setTextIsSelectable(false) })
        val consent=CheckBox(activity).apply { setText(R.string.managed_replace_journal);isSaveEnabled=false }
        if(needsConsent) content.addView(consent)
        val d=AlertDialog.Builder(activity).setTitle(title).setView(ScrollView(activity).apply { addView(content) })
            .setNegativeButton(R.string.managed_cancel,null).setPositiveButton(R.string.managed_confirm,null).create()
        if(!session.attach(ticket) { cancel();if(dialog===d) dialog=null;d.dismiss() }) return false
        dialog=d
        d.setOnDismissListener { if(dialog===d) { dialog=null;session.invalidate() } }
        d.show();d.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val positive=d.getButton(AlertDialog.BUTTON_POSITIVE)
        positive.isEnabled=!needsConsent
        consent.setOnCheckedChangeListener { _,checked -> positive.isEnabled=checked && session.permits(ticket) }
        positive.setOnClickListener {
            if(!session.permits(ticket) || (needsConsent && !consent.isChecked)) { d.dismiss();return@setOnClickListener }
            positive.isEnabled=false
            val result=runCatching { confirm(consent.isChecked) }.getOrDefault(ManagedCrashTransaction.Outcome.UNAVAILABLE)
            session.invalidate();complete(ManagedReviewMessages.outcome(result))
        }
        return true
    }
}
