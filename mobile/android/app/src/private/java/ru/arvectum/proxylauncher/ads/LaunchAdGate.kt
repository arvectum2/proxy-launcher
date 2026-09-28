package ru.arvectum.proxylauncher.ads

import android.app.Activity

class LaunchAdGate(
    @Suppress("UNUSED_PARAMETER") activity: Activity,
    private val onComplete: () -> Unit,
) {
    fun start() {
        onComplete()
    }

    fun destroy() = Unit
}
