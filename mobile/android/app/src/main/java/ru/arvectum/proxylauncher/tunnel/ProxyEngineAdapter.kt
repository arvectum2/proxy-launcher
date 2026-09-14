package ru.arvectum.proxylauncher.tunnel

import android.os.ParcelFileDescriptor
import com.github.shadowsocks.bg.Tun2proxy
import java.net.URI
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType

/**
 * Engine boundary. UI/profile storage are intentionally independent from tun2proxy,
 * sing-box or any future engine.
 */
interface ProxyEngineAdapter {
    /** Blocking call: run it on a dedicated worker thread. */
    fun run(tun: ParcelFileDescriptor, profile: ProxyProfile, password: String?): Int
    fun stop(): Int
}

class Tun2ProxyEngineAdapter : ProxyEngineAdapter {
    override fun run(tun: ParcelFileDescriptor, profile: ProxyProfile, password: String?): Int {
        val proxyUrl = buildProxyUrl(profile, password)
        val args = buildString {
            append("tun2proxy-bin")
            append(" --tun-fd ").append(tun.fd)
            append(" --close-fd-on-drop false")
            append(" --proxy ").append(proxyUrl)
            append(" --dns virtual")
            append(" --verbosity warn")
        }
        return Tun2proxy.run(args, TUN_MTU.toChar())
    }

    override fun stop(): Int = Tun2proxy.stop()

    private fun buildProxyUrl(profile: ProxyProfile, password: String?): String {
        val scheme = when (profile.type) {
            ProxyType.SOCKS5 -> "socks5"
            ProxyType.HTTP -> "http"
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
