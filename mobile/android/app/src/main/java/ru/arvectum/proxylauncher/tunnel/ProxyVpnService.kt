package ru.arvectum.proxylauncher.tunnel

import android.content.Intent
import android.net.VpnService
import android.os.IBinder

class ProxyVpnService : VpnService() {
    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onDestroy() {
        super.onDestroy()
    }

    companion object {
        const val ACTION_CONNECT = "ru.arvectum.proxylauncher.CONNECT"
        const val ACTION_DISCONNECT = "ru.arvectum.proxylauncher.DISCONNECT"
    }
}
