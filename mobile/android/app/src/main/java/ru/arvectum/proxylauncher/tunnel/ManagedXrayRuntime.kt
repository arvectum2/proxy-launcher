package ru.arvectum.proxylauncher.tunnel

import libXray.DialerController
import libXray.LibXray
import org.json.JSONObject
import ru.arvectum.proxylauncher.model.ManagedProxyProfile

data class LocalSocksEndpoint(
    val host: String,
    val port: Int,
)

/**
 * Small wrapper around pinned libXray. Keeping the raw gomobile API here makes
 * the rest of the APL tunnel lifecycle independent from upstream API churn.
 */
interface ManagedTransportRuntime {
    fun start(
        profile: ManagedProxyProfile,
        localSocksPort: Int,
        dnsServer: String,
        protectSocket: (Int) -> Boolean,
    ): LocalSocksEndpoint

    fun stop()
}

class LibXrayManagedTransportRuntime : ManagedTransportRuntime {
    @Volatile private var running = false

    override fun start(
        profile: ManagedProxyProfile,
        localSocksPort: Int,
        dnsServer: String,
        protectSocket: (Int) -> Boolean,
    ): LocalSocksEndpoint {
        check(!running) { "Managed Xray runtime is already active" }
        require(dnsServer.isNotBlank()) { "Physical DNS endpoint is required" }

        val controller = object : DialerController {
            override fun protectFd(fd: Long): Boolean = protectSocket(fd.toInt())
        }

        LibXray.registerDialerController(controller)
        LibXray.setDNS(controller, dnsServer)

        val config = ManagedXrayConfig.render(profile, localSocksPort)
        try {
            invokeOrThrow(
                method = "testXray",
                payload = JSONObject().put("xrayJson", config),
            )
            invokeOrThrow(
                method = "runXray",
                payload = JSONObject().put("xrayJson", config),
            )
            running = true
            return LocalSocksEndpoint(ManagedXrayConfig.LOCAL_HOST, localSocksPort)
        } catch (error: Throwable) {
            runCatching { LibXray.resetDNS() }
            throw error
        }
    }

    override fun stop() {
        if (!running) {
            runCatching { LibXray.resetDNS() }
            return
        }
        try {
            invokeOrThrow(method = "stopXray", payload = null)
        } finally {
            running = false
            runCatching { LibXray.resetDNS() }
        }
    }

    private fun invokeOrThrow(method: String, payload: JSONObject?) {
        val request = JSONObject()
            .put("apiVersion", LibXray.LibXrayAPIVersion)
            .put("method", method)
        if (payload != null) request.put("payload", payload)

        val response = JSONObject(LibXray.invoke(request.toString()))
        if (!response.optBoolean("success", false)) {
            val detail = response.optString("error").ifBlank { "unknown libXray error" }
            throw IllegalStateException("$method failed: $detail")
        }
    }
}
