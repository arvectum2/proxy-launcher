package ru.arvectum.proxylauncher.model

import com.google.zxing.PlanarYUVLuminanceSource
import java.nio.ByteBuffer

/** Bounded camera Y-plane adapter; independent of Android hardware and frame lifecycle. */
object ProxyQrCameraFrame {
    const val MAX_SIDE = 1280
    const val MAX_PIXELS = 1_228_800

    fun supportedSize(width: Int, height: Int): Boolean =
        width in 1..MAX_SIDE && height in 1..MAX_SIDE &&
            width.toLong() * height <= MAX_PIXELS

    internal fun packLuma(width: Int, height: Int, plane: ByteBuffer,
                          rowStride: Int, pixelStride: Int): ByteArray? {
        if (!supportedSize(width, height) || rowStride <= 0 || pixelStride <= 0) return null
        val rowBytes = (width - 1L) * pixelStride + 1
        val needed = (height - 1L) * rowStride + rowBytes
        if (rowBytes > rowStride || needed > plane.remaining()) return null
        val src = plane.slice()
        val pixels = ByteArray(width * height)
        if (pixelStride == 1) {
            for (y in 0 until height) {
                src.position(y * rowStride)
                src.get(pixels, y * width, width)
            }
        } else {
            for (y in 0 until height) for (x in 0 until width) {
                pixels[y * width + x] = src.get(y * rowStride + x * pixelStride)
            }
        }
        return pixels
    }

    fun decode(width: Int, height: Int, plane: ByteBuffer,
               rowStride: Int, pixelStride: Int): List<ImportedProxy>? {
        val pixels = packLuma(width, height, plane, rowStride, pixelStride) ?: return null
        return try {
            ProxyQrImport.decodeLuminance(PlanarYUVLuminanceSource(
                pixels, width, height, 0, 0, width, height, false))
        } finally { pixels.fill(0) }
    }
}
