package ru.arvectum.proxylauncher.model

import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream

class ProxyQrImportTest {
    private fun qr(text: String, side: Int = 320): IntArray {
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, side, side)
        return IntArray(side * side) { index -> if (matrix.get(index % side, index / side)) 0xff000000.toInt() else -1 }
    }

    @Test fun realQrRoundtrip() {
        val pixels = qr("socks5://demo:p%40ss@proxy.invalid:1080#Example")
        val item = ProxyQrImport.decodePixels(320, 320, pixels)!!.single()
        assertEquals(ProxyType.SOCKS5, item.type)
        assertEquals("p@ss", item.password)
        assertEquals("Example", item.name)
    }

    @Test fun iosEnvelopeRoundtrip() {
        val envelope = "arvectum-proxy://import?data=https://demo:p%252B%2540@proxy.invalid:443%23Test"
        val item = ProxyQrImport.decodePixels(320, 320, qr(envelope))!!.single()
        assertEquals("p+@", item.password)
        assertEquals("Test", item.name)
        assertEquals("a+b", ProxyQrImport.parsePayload("arvectum-proxy://import?data=http://demo:a+b@proxy.invalid:80")!!.single().password)
    }

    @Test fun badEnvelopesAndUnsupportedPayloads() {
        for (text in listOf(
            "arvectum-proxy://other?data=http://proxy.invalid:80",
            "arvectum-proxy://import/path?data=http://proxy.invalid:80",
            "arvectum-proxy://import?data=http://proxy.invalid:80&data=http://other.invalid:80",
            "arvectum-proxy://import?data=http://proxy.invalid:80#fragment",
            "arvectum-proxy://import?data=http://proxy.invalid:80%0Aother.invalid:81",
            "arvectum-proxy://import?data=vless://host:443",
            "arvectum-proxy://import?data=%XX",
            "https://example.invalid/page",
            "vless://proxy.invalid:443"
        )) assertNull(ProxyQrImport.decodePixels(320, 320, qr(text)))
    }

    @Test fun multipleQrAndBlankRejected() {
        val w = 700
        val h = 360
        val pixels = IntArray(w * h) { -1 }
        val a = qr("proxy.invalid:80", 280)
        val b = qr("other.invalid:81", 280)
        for (y in 0 until 280) {
            a.copyInto(pixels, (y + 40) * w + 20, y * 280, (y + 1) * 280)
            b.copyInto(pixels, (y + 40) * w + 400, y * 280, (y + 1) * 280)
        }
        assertNull(ProxyQrImport.decodePixels(w, h, pixels))
        assertNull(ProxyQrImport.decodePixels(320, 320, IntArray(320 * 320) { -1 }))
    }

    @Test fun imageBoundsAndStreamLimit() {
        assertEquals(1, ProxyQrImport.sampleSize(2048, 1024))
        assertEquals(2, ProxyQrImport.sampleSize(4000, 3000))
        assertNull(ProxyQrImport.sampleSize(4001, 3000))
        assertNull(ProxyQrImport.sampleSize(Int.MAX_VALUE, Int.MAX_VALUE))
        assertNull(ProxyQrImport.sampleSize(0, 1))
        assertNull(ProxyQrImport.decodePixels(2049, 1, IntArray(2049)))
        assertNull(ProxyQrImport.decodePixels(1, 1, IntArray(0)))
        assertNull(ProxyQrImport.readEncoded(ByteArrayInputStream(ByteArray(0))))
        assertNull(ProxyQrImport.readEncoded(ByteArrayInputStream(ByteArray(ProxyQrImport.MAX_ENCODED_BYTES + 1))))
        assertArrayEquals(byteArrayOf(1,2), ProxyQrImport.readEncoded(byteArrayOf(1,2).inputStream()))
    }
}
