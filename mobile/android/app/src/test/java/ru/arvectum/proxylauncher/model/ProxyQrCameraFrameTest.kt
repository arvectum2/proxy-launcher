package ru.arvectum.proxylauncher.model

import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test

class ProxyQrCameraFrameTest {
    @Test fun paddedRowsAndPixelStride() {
        val buffer = ByteBuffer.wrap(byteArrayOf(99, 1, 88, 2, 77, 66, 3, 55, 4))
        buffer.position(1)
        val packed = ProxyQrCameraFrame.packLuma(2, 2, buffer, 5, 2)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), packed)
        assertEquals(1, buffer.position())
        assertArrayEquals(byteArrayOf(1,2,3,4), ProxyQrCameraFrame.packLuma(
            2,2,ByteBuffer.wrap(byteArrayOf(1,2,99,3,4)),3,1))
    }

    @Test fun malformedOrOversizeRejected() {
        val bytes = ByteBuffer.allocate(16)
        assertNull(ProxyQrCameraFrame.packLuma(4,4,bytes,3,1))
        assertNull(ProxyQrCameraFrame.packLuma(4,4,bytes,4,2))
        assertNull(ProxyQrCameraFrame.packLuma(4,4,bytes,5,1))
        assertNull(ProxyQrCameraFrame.packLuma(4,4,bytes,Int.MAX_VALUE,Int.MAX_VALUE))
        assertNull(ProxyQrCameraFrame.packLuma(0,4,bytes,4,1))
        assertFalse(ProxyQrCameraFrame.supportedSize(1280,1280))
        assertTrue(ProxyQrCameraFrame.supportedSize(1280,960))
        assertFalse(ProxyQrCameraFrame.supportedSize(1281,1))
    }

    @Test fun decodeRealQrFromStridedFrame() {
        val side = 320
        val row = side * 2 + 16
        val qr = QRCodeWriter().encode("socks5://demo:fake@proxy.invalid:1080", BarcodeFormat.QR_CODE, side, side)
        val bytes = ByteBuffer.allocateDirect(row * side + 3)
        bytes.position(3)
        for (y in 0 until side) for (x in 0 until side) {
            bytes.put(3 + y * row + x * 2, if (qr.get(x,y)) 0 else 255.toByte())
        }
        val item = ProxyQrCameraFrame.decode(side, side, bytes, row, 2)!!.single()
        assertEquals("proxy.invalid", item.host)
        assertEquals(ProxyType.SOCKS5, item.type)
        assertEquals("fake", item.password)
        assertEquals(3, bytes.position())
    }
}
