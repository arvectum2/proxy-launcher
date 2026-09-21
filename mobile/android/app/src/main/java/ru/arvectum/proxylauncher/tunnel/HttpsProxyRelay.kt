package ru.arvectum.proxylauncher.tunnel

import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import kotlin.concurrent.thread

/**
 * TLS wrapper for a standard HTTPS proxy.
 *
 * tun2proxy speaks HTTP CONNECT. For an https:// proxy we expose a local plain HTTP
 * proxy endpoint to tun2proxy and encrypt that byte stream to the real upstream.
 */
class HttpsProxyRelay(
    private val upstreamHost: String,
    private val upstreamPort: Int,
) {
    private val server = ServerSocket(0, 50, InetAddress.getByName(LOOPBACK_HOST))
    private val sockets = ConcurrentHashMap.newKeySet<Socket>()
    @Volatile private var running = false

    val localHost: String get() = LOOPBACK_HOST
    val localPort: Int get() = server.localPort

    fun start() {
        if (running) return
        running = true
        thread(name = "APL-https-proxy-relay", isDaemon = true) {
            while (running) {
                val local = try {
                    server.accept()
                } catch (_: Exception) {
                    break
                }
                sockets += local
                thread(name = "APL-https-proxy-client", isDaemon = true) { handle(local) }
            }
        }
    }

    fun stop() {
        running = false
        runCatching { server.close() }
        sockets.toList().forEach { runCatching { it.close() } }
        sockets.clear()
    }

    private fun handle(local: Socket) {
        var upstreamForCleanup: SSLSocket? = null
        try {
            local.tcpNoDelay = true
            val upstream = SSLSocketFactory.getDefault().createSocket() as SSLSocket
            upstreamForCleanup = upstream
            upstream.connect(InetSocketAddress(upstreamHost, upstreamPort), CONNECT_TIMEOUT_MS)
            upstream.sslParameters = upstream.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
            upstream.startHandshake()
            upstream.tcpNoDelay = true
            sockets += upstream

            thread(name = "APL-https-proxy-up", isDaemon = true) {
                relayPumpSafely(local.getInputStream(), upstream.getOutputStream())
                runCatching { upstream.shutdownOutput() }
            }
            relayPumpSafely(upstream.getInputStream(), local.getOutputStream())
        } catch (_: Exception) {
            // A failure establishing this one CONNECT must never crash the :vpn process.
        } finally {
            upstreamForCleanup?.let {
                sockets -= it
                runCatching { it.close() }
            }
            sockets -= local
            runCatching { local.close() }
        }
    }

    internal fun relayPumpSafely(
        input: InputStream,
        output: OutputStream,
    ): RelayPumpOutcome {
        return try {
            val buffer = ByteArray(BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                output.write(buffer, 0, count)
                output.flush()
            }
            RelayPumpOutcome.EOF
        } catch (_: IOException) {
            // Socket close/reset/broken-pipe is a per-CONNECT lifecycle event.
            RelayPumpOutcome.IO_CLOSED
        }
    }

    companion object {
        internal const val LOOPBACK_HOST = "127.0.0.1"
        private const val CONNECT_TIMEOUT_MS = 5000
        private const val BUFFER_SIZE = 32 * 1024
    }
}

internal enum class RelayPumpOutcome {
    EOF,
    IO_CLOSED,
}
