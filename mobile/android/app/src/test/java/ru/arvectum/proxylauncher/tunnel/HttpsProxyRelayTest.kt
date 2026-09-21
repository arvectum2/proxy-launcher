package ru.arvectum.proxylauncher.tunnel

import org.junit.Assert.assertEquals
import org.junit.Test

class HttpsProxyRelayTest {
    @Test
    fun bindsToSameIpv4LoopbackAdvertisedToTun2proxy() {
        val relay = HttpsProxyRelay("example.com", 443)
        try {
            assertEquals("127.0.0.1", relay.localHost)
            assertEquals("127.0.0.1", HttpsProxyRelay.LOOPBACK_HOST)
        } finally {
            relay.stop()
        }
    }
}
