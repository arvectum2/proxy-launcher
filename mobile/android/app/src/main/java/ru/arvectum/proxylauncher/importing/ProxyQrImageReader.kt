package ru.arvectum.proxylauncher.importing

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.InputStream
import ru.arvectum.proxylauncher.model.ImportedProxy
import ru.arvectum.proxylauncher.model.ProxyQrImport

object ProxyQrImageReader {
    fun read(stream: InputStream): List<ImportedProxy>? {
        val bytes = ProxyQrImport.readEncoded(stream) ?: return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            if (bounds.outMimeType !in setOf("image/png", "image/jpeg", "image/webp")) return null
            val sample = ProxyQrImport.sampleSize(bounds.outWidth, bounds.outHeight) ?: return null
            val options = BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
                inScaled = false
            }
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return null
            try {
                val w = bitmap.width
                val h = bitmap.height
                if (w !in 1..ProxyQrImport.MAX_DECODED_SIDE || h !in 1..ProxyQrImport.MAX_DECODED_SIDE) return null
                val pixels = IntArray(w * h)
                try {
                    bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
                    ProxyQrImport.decodePixels(w, h, pixels)
                } finally { pixels.fill(0) }
            } finally { bitmap.recycle() }
        } catch (_: Exception) { null }
        finally { bytes.fill(0) }
    }
}
