package ru.arvectum.proxylauncher.tunnel

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import ru.arvectum.proxylauncher.storage.SecureProfileStore

/**
 * Runs in the default app process, not :vpn. A fresh VPN process is required
 * because tun2proxy intentionally terminates its hosting process after stop.
 */
class FailoverRestartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ProxyVpnService.ACTION_FAILOVER_RESTART) return
        val pendingResult = goAsync()
        Thread({
            try {
                Thread.sleep(HANDOFF_DELAY_MS)
                val store = SecureProfileStore(context)
                if (!store.consumeFailoverRestartPending()) return@Thread
                val serviceIntent = Intent(context, ProxyVpnService::class.java)
                    .setAction(ProxyVpnService.ACTION_CONNECT)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            } catch (_: Exception) {
                SecureProfileStore(context).setLastState(
                    ProxyVpnService.STATE_ERROR,
                    "Не удалось автоматически перезапустить VPN",
                )
            } finally {
                pendingResult.finish()
            }
        }, "APL-failover-handoff").start()
    }

    companion object {
        private const val HANDOFF_DELAY_MS = 900L
    }
}
