package ru.arvectum.proxylauncher.model

import org.junit.Assert.*
import org.junit.Test

class ProxyQrExportTest {
    @Test fun portableEnvelopeRoundTrip() {
        for (type in listOf(ProxyType.HTTP, ProxyType.HTTPS, ProxyType.SOCKS5)) {
            val profile = ProxyProfile("synthetic", "Тест + &", "2001:db8::1", 1080, type, "user+@")
            val link = ProxyQrExport.deepLink(profile, "p+&:@%雪")!!
            assertTrue(link.startsWith("arvectum-proxy://import?data="))
            val result = ProxyQrImport.parsePayload(link)!!.single()
            assertEquals(profile.name, result.name)
            assertEquals(profile.host, result.host)
            assertEquals(profile.port, result.port)
            assertEquals(profile.type, result.type)
            assertEquals(profile.username, result.username)
            assertEquals("p+&:@%雪", result.password)
        }
    }

    @Test fun qrPixelsRoundTripWithQuietZone() {
        val profile = ProxyProfile("synthetic", "Example", "proxy.invalid", 443, ProxyType.HTTPS, "demo")
        val matrix = ProxyQrExport.matrix(profile, "fake-password")!!
        assertEquals(matrix.width, matrix.height)
        for (x in 0 until matrix.width) for (y in 0..3) {
            assertFalse(matrix.get(x, y))
            assertFalse(matrix.get(x, matrix.height - 1 - y))
            assertFalse(matrix.get(y, x))
            assertFalse(matrix.get(matrix.width - 1 - y, x))
        }
        val side = matrix.width * 5
        val pixels = IntArray(side * side) { i ->
            if (matrix.get((i % side) / 5, (i / side) / 5)) 0xff000000.toInt() else -1
        }
        val item = ProxyQrImport.decodePixels(side, side, pixels)!!.single()
        assertEquals("proxy.invalid", item.host)
        assertEquals("fake-password", item.password)
        assertEquals("Example", item.name)
    }

    @Test fun refusesUnsupportedAndLossyProfiles() {
        val base = ProxyProfile("synthetic", "Name", "proxy.invalid", 80, ProxyType.HTTP)
        assertNotNull(ProxyQrExport.deepLink(base, null))
        assertNull(ProxyQrExport.deepLink(base.copy(type = ProxyType.AUTO), null))
        assertNull(ProxyQrExport.deepLink(base, "orphan"))
        assertNull(ProxyQrExport.deepLink(base.copy(host = "host@other.invalid"), null))
        assertNull(ProxyQrExport.deepLink(base.copy(username = "a:b"), "fake"))
        assertNull(ProxyQrExport.deepLink(base.copy(name = " Name "), null))
        assertNull(ProxyQrExport.deepLink(base.copy(username = "demo"), "雪".repeat(800)))
    }
}
