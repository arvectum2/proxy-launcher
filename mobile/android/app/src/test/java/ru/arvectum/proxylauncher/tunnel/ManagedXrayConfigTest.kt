package ru.arvectum.proxylauncher.tunnel

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import ru.arvectum.proxylauncher.model.ManagedProxyProfile

class ManagedXrayConfigTest {
    private val profile = ManagedProxyProfile(
        id = "managed-nl-shared",
        name = "Netherlands Shared",
        host = "nl01.managed.arvectum.test",
        port = 443,
        credentialId = "11111111-2222-4333-8444-555555555555",
        serverName = "www.microsoft.com",
        realityPassword = "TEST_REALITY_PASSWORD_PUBLIC_MATERIAL",
        realityShortId = "a1b2c3d4e5f60708",
    )

    @Test
    fun rendersLoopbackSocksAndCurrentVlessRealityOutbound() {
        val root = JSONObject(ManagedXrayConfig.render(profile, 18587))
        val inbound = root.getJSONArray("inbounds").getJSONObject(0)
        assertEquals("127.0.0.1", inbound.getString("listen"))
        assertEquals(18587, inbound.getInt("port"))
        assertEquals("socks", inbound.getString("protocol"))
        assertTrue(inbound.getJSONObject("settings").getBoolean("udp"))

        val outbound = root.getJSONArray("outbounds").getJSONObject(0)
        assertEquals("vless", outbound.getString("protocol"))
        val settings = outbound.getJSONObject("settings")
        assertEquals(profile.host, settings.getString("address"))
        assertEquals(profile.port, settings.getInt("port"))
        assertEquals(profile.credentialId, settings.getString("id"))
        assertEquals("none", settings.getString("encryption"))
        assertEquals("xtls-rprx-vision", settings.getString("flow"))

        val stream = outbound.getJSONObject("streamSettings")
        assertEquals("raw", stream.getString("network"))
        assertEquals("reality", stream.getString("security"))
        val reality = stream.getJSONObject("realitySettings")
        assertEquals(profile.serverName, reality.getString("serverName"))
        assertEquals(profile.realityPassword, reality.getString("password"))
        assertEquals(profile.realityShortId, reality.getString("shortId"))
        assertEquals("chrome", reality.getString("fingerprint"))
    }

    @Test
    fun clientConfigDoesNotContainServerPrivateOrSupplierCredentialFields() {
        val rendered = ManagedXrayConfig.render(profile, 18587)
        assertFalse(rendered.contains("privateKey"))
        assertFalse(rendered.contains("supplier", ignoreCase = true))
        assertFalse(rendered.contains("upstreamPassword"))
    }

    @Test
    fun validatesRealityShortIdAndLocalPort() {
        assertThrows(IllegalArgumentException::class.java) {
            profile.copy(realityShortId = "abc")
        }
        assertThrows(IllegalArgumentException::class.java) {
            profile.copy(realityShortId = "zz")
        }
        assertThrows(IllegalArgumentException::class.java) {
            ManagedXrayConfig.render(profile, 0)
        }
    }
}
