package ru.arvectum.proxylauncher

import ru.arvectum.proxylauncher.ui.ManagedReviewDialogs

/** Notification target and disposable lifecycle host, not production UI. */
class MainActivity:android.app.Activity() {
    internal val reviews by lazy { ManagedReviewDialogs(this) }
    override fun onResume() { super.onResume();reviews.update(true,true,null) }
    override fun onPause() { reviews.update(false,true,null);super.onPause() }
    override fun onDestroy() { reviews.invalidate();super.onDestroy() }
}
