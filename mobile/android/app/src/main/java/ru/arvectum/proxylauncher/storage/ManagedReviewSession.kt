package ru.arvectum.proxylauncher.storage

/** Dormant, main-thread UI session. A fetch/review is invalidated even if the old
 * selection or disconnected state later returns. No network or store calls here. */
internal class ManagedReviewSession {
    internal class Ticket internal constructor()
    private var current: Ticket? = null
    private var cancelReview: (() -> Unit)? = null
    private var foreground = false
    private var disconnected = false
    private var selected: String? = null

    fun update(foreground: Boolean, disconnected: Boolean, selected: String?) {
        if (this.foreground != foreground || this.disconnected != disconnected || this.selected != selected) invalidate()
        this.foreground = foreground
        this.disconnected = disconnected
        this.selected = selected
    }

    fun begin(): Ticket? {
        invalidate()
        if (!foreground || !disconnected) return null
        return Ticket().also { current = it }
    }

    fun permits(ticket: Ticket): Boolean = current === ticket && foreground && disconnected

    /** One review per ticket; stale completion is disposed without replacing the current review. */
    fun attach(ticket: Ticket, cancel: () -> Unit): Boolean {
        if (!permits(ticket) || cancelReview != null) { cancel(); return false }
        cancelReview = cancel
        return true
    }

    fun invalidate() {
        current = null
        val cancel = cancelReview
        cancelReview = null
        cancel?.invoke()
    }
}
