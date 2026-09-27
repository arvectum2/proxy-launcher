package ru.arvectum.proxylauncher.tunnel

import org.json.JSONArray
import org.json.JSONObject
import ru.arvectum.proxylauncher.model.ManagedProxyProfile

/**
 * Renders the client-side Xray configuration used only inside the :vpn process.
 *
 * Existing APL routing remains TUN -> tun2proxy. Xray exposes one loopback
 * SOCKS5 listener and transports that traffic to the Arvectum VLESS/REALITY
 * node. No upstream supplier credentials are present in this client config.
 */
object ManagedXrayConfig {
    const val LOCAL_HOST = "127.0.0.1"

    fun render(profile: ManagedProxyProfile, localSocksPort: Int): String {
        require(localSocksPort in 1..65535) { "Local SOCKS port must be between 1 and 65535" }

        val socksInbound = JSONObject()
            .put("tag", "apl-local-socks")
            .put("listen", LOCAL_HOST)
            .put("port", localSocksPort)
            .put("protocol", "socks")
            .put(
                "settings",
                JSONObject()
                    .put("auth", "noauth")
                    .put("udp", true)
                    .put("ip", LOCAL_HOST),
            )

        val reality = JSONObject()
            .put("serverName", profile.serverName)
            .put("fingerprint", profile.fingerprint)
            .put("password", profile.realityPassword)
            .put("shortId", profile.realityShortId)
            .put("spiderX", "")

        val managedOutbound = JSONObject()
            .put("tag", "apl-managed-vless")
            .put("protocol", "vless")
            .put(
                "settings",
                JSONObject()
                    .put("address", profile.host)
                    .put("port", profile.port)
                    .put("id", profile.credentialId)
                    .put("encryption", "none")
                    .put("flow", "xtls-rprx-vision"),
            )
            .put(
                "streamSettings",
                JSONObject()
                    .put("network", "raw")
                    .put("security", "reality")
                    .put("realitySettings", reality),
            )

        val route = JSONObject()
            .put("type", "field")
            .put("inboundTag", JSONArray().put("apl-local-socks"))
            .put("outboundTag", "apl-managed-vless")

        return JSONObject()
            .put("log", JSONObject().put("loglevel", "warning"))
            .put("inbounds", JSONArray().put(socksInbound))
            .put(
                "outbounds",
                JSONArray()
                    .put(managedOutbound)
                    .put(JSONObject().put("tag", "direct").put("protocol", "freedom")),
            )
            .put(
                "routing",
                JSONObject()
                    .put("domainStrategy", "AsIs")
                    .put("rules", JSONArray().put(route)),
            )
            .toString()
    }
}
