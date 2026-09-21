package ru.arvectum.proxylauncher.tunnel

import android.os.ParcelFileDescriptor
import com.github.shadowsocks.bg.Tun2proxy
import java.net.Socket
import java.net.URI
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType

enum class TunnelDnsMode(val cliValue: String) {
    VIRTUAL("virtual"),
    DIRECT("direct"),
}

interface ProxyEngineAdapter {
    fun run(
        tun: ParcelFileDescriptor,
        profile: ProxyProfile,
        password: String?,
        dnsMode: TunnelDnsMode = TunnelDnsMode.VIRTUAL,
    ): Int
    fun stop(): Int
}

class Tun2ProxyEngineAdapter(
    private val protectSocket: ((Socket) -> Boolean)? = null,
) : ProxyEngineAdapter {
    @Volatile private var activeRelay: HttpsProxyRelay? = null

    override fun run(
        tun: ParcelFileDescriptor,
        profile: ProxyProfile,
        password: String?,
        dnsMode: TunnelDnsMode,
    ): Int {
        require(profile.type != ProxyType.AUTO) { "AUTO proxy type must be resolved before engine start" }

        val relay = if (profile.type == ProxyType.HTTPS) {
            HttpsProxyRelay(profile.host, profile.port, protectSocket).also {
                it.start()
                activeRelay = it
            }
        } else {
            null
        }

        val effectiveProfile = if (relay != null) {
            profile.copy(host = relay.localHost, port = relay.localPort, type = ProxyType.HTTP)
        } else {
            profile
        }

        val proxyUrl = buildProxyUrl(effectiveProfile, password)
        val args = buildString {
            append("tun2proxy-bin")
            append(" --tun-fd ").append(tun.fd)
            append(" --close-fd-on-drop false")
            append(" --proxy ").append(proxyUrl)
            append(" --dns ").append(dnsMode.cliValue)
            append(" --ipv6-enabled")
            append(" --verbosity warn")
        }

        return try {
            Tun2proxy.run(args, TUN_MTU.toChar())
        } finally {
            relay?.stop()
            if (activeRelay === relay) activeRelay = null
        }
    }

    override fun stop(): Int {
        val result = runCatching { Tun2proxy.stop() }.getOrDefault(-1)
        activeRelay?.stop()
        activeRelay = null
        return result
    }

    private fun buildProxyUrl(profile: ProxyProfile, password: String?): String {
        val scheme = when (profile.type) {
            ProxyType.SOCKS5 -> "socks5"
            ProxyType.HTTP -> "http"
            ProxyType.HTTPS -> error("HTTPS must be wrapped before URL construction")
            ProxyType.AUTO -> error("AUTO must be resolved before URL construction")
        }
        val userInfo = profile.username?.let { username ->
            if (password != null) "$username:$password" else username
        }
        return URI(scheme, userInfo, profile.host, profile.port, null, null, null).toASCIIString()
    }

    companion object {
        const val TUN_MTU = 1500
    }
}
