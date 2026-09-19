package ru.arvectum.proxylauncher.tunnel

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import ru.arvectum.proxylauncher.model.ProxyHealthStatus
import ru.arvectum.proxylauncher.storage.PoolUiStateStore

/**
 * Receives non-secret pool telemetry from :vpn and persists it in the default
 * app process. This keeps SharedPreferences single-process on both sides.
 */
class PoolStateRelayReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val store = PoolUiStateStore(context)

        when (action) {
            ProxyVpnService.ACTION_POOL_STATE -> {
                val state = intent.getStringExtra(ProxyVpnService.EXTRA_STATE) ?: return
                store.setTunnelState(
                    state = state,
                    detail = intent.getStringExtra(ProxyVpnService.EXTRA_DETAIL),
                )
                return
            }
            ProxyVpnService.ACTION_POOL_HEALTH -> {
                val profileId = intent.getStringExtra(ProxyVpnService.EXTRA_PROFILE_ID) ?: return
                val status = runCatching {
                    ProxyHealthStatus.valueOf(
                        intent.getStringExtra(ProxyVpnService.EXTRA_HEALTH_STATUS).orEmpty(),
                    )
                }.getOrNull() ?: return
                val latency = if (intent.hasExtra(ProxyVpnService.EXTRA_LATENCY_MS)) {
                    intent.getLongExtra(ProxyVpnService.EXTRA_LATENCY_MS, 0L)
                } else {
                    null
                }
                store.setHealth(
                    profileId = profileId,
                    status = status,
                    latencyMs = latency,
                    checkedAtMs = intent.getLongExtra(
                        ProxyVpnService.EXTRA_TIMESTAMP_MS,
                        System.currentTimeMillis(),
                    ),
                )
            }
            ProxyVpnService.ACTION_POOL_EVENT -> {
                store.appendEvent(
                    type = intent.getStringExtra(ProxyVpnService.EXTRA_EVENT_TYPE) ?: return,
                    profileId = intent.getStringExtra(ProxyVpnService.EXTRA_PROFILE_ID),
                    profileName = intent.getStringExtra(ProxyVpnService.EXTRA_PROFILE_NAME),
                    detail = intent.getStringExtra(ProxyVpnService.EXTRA_EVENT_DETAIL),
                    timestampMs = intent.getLongExtra(
                        ProxyVpnService.EXTRA_TIMESTAMP_MS,
                        System.currentTimeMillis(),
                    ),
                )
            }
            else -> return
        }

        context.sendBroadcast(
            Intent(ProxyVpnService.ACTION_POOL_UPDATE)
                .setPackage(context.packageName),
        )
    }
}
