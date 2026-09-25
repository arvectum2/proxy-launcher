package ru.arvectum.proxylauncher.tunnel

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
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
    @Test
    fun socketIoFailureIsContainedInsideSingleRelayPump() {
        val relay = HttpsProxyRelay("example.com", 443)
        try {
            val throwingInput = object : InputStream() {
                override fun read(): Int = throw IOException("connection reset")
                override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
                    throw IOException("connection reset")
            }
            assertEquals(
                RelayPumpOutcome.IO_CLOSED,
                relay.relayPumpSafely(throwingInput, ByteArrayOutputStream()),
            )
        } finally {
            relay.stop()
        }
    }

    @Test
    fun normalRelayPumpCopiesPayloadUntilEof() {
        val relay = HttpsProxyRelay("example.com", 443)
        try {
            val payload = "hello-through-relay".toByteArray()
            val output = ByteArrayOutputStream()
            assertEquals(
                RelayPumpOutcome.EOF,
                relay.relayPumpSafely(ByteArrayInputStream(payload), output),
            )
            assertArrayEquals(payload, output.toByteArray())
        } finally {
            relay.stop()
        }
    }

}
