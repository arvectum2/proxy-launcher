package ru.arvectum.proxylauncher.tunnel

import android.os.SystemClock
import java.net.HttpURLConnection
import java.net.URL

class FreeTunnelDataPathProbe(
    private val probeUrl: String = DEFAULT_PROBE_URL,
) {
    fun measureLatencyMs(): Long {
        val started = SystemClock.elapsedRealtime()
        val connection = URL(probeUrl).openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.useCaches = false
            connection.setRequestProperty("Cache-Control", "no-cache")
            connection.setRequestProperty("Connection", "close")
            val status = connection.responseCode
            if (status !in 200..399) {
                throw IllegalStateException("Data-path probe returned HTTP " + status)
            }
            connection.inputStream.use { stream ->
                if (stream.read() < 0) {
                    throw IllegalStateException("Data-path probe returned an empty response")
                }
            }
            (SystemClock.elapsedRealtime() - started).coerceAtLeast(0L)
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        const val DEFAULT_PROBE_URL = "https://example.com/"
        private const val CONNECT_TIMEOUT_MS = 10_000
        private const val READ_TIMEOUT_MS = 10_000
    }
}
