package ru.arvectum.proxylauncher.tunnel

import android.os.ParcelFileDescriptor
import ru.arvectum.proxylauncher.model.ManagedProxyProfile
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType

/**
 * Additive managed transport seam:
 *
 * Android TUN -> existing tun2proxy -> loopback SOCKS5 -> libXray ->
 * Arvectum VLESS/REALITY node.
 *
 * Keeping tun2proxy as the TUN owner preserves the accepted app/site exclusion
 * and lifecycle path. Xray only owns the encrypted managed transport.
 */
class ManagedProxyEngineAdapter(
    private val managedRuntime: ManagedTransportRuntime,
    private val tunnelEngine: ProxyEngineAdapter,
) {
    fun run(
        tun: ParcelFileDescriptor,
        profile: ManagedProxyProfile,
        localSocksPort: Int,
        dnsServer: String,
        protectSocket: (Int) -> Boolean,
        dnsMode: TunnelDnsMode = TunnelDnsMode.VIRTUAL,
    ): Int {
        val endpoint = managedRuntime.start(
            profile = profile,
            localSocksPort = localSocksPort,
            dnsServer = dnsServer,
            protectSocket = protectSocket,
        )
        val loopbackProfile = ProxyProfile(
            id = "managed-local-${profile.id}",
            name = profile.name,
            host = endpoint.host,
            port = endpoint.port,
            type = ProxyType.SOCKS5,
        )
        return try {
            tunnelEngine.run(tun, loopbackProfile, password = null, dnsMode = dnsMode)
        } finally {
            managedRuntime.stop()
        }
    }

    fun stop() {
        runCatching { tunnelEngine.stop() }
        runCatching { managedRuntime.stop() }
    }
}
