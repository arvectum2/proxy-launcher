package ru.arvectum.proxylauncher.ads

import android.app.Activity

object AppOpenAdGate {
    fun open(activity: Activity, proceed: () -> Unit) {
        proceed()
    }

    fun cancel(activity: Activity) = Unit
}
