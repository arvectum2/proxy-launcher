package ru.arvectum.proxylauncher.tunnel

import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.io.IOException
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
    private val protectSocket: ((Socket) -> Boolean)? = null,
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
            if (protectSocket != null && !protectSocket.invoke(upstream)) {
                throw IOException("Unable to protect HTTPS relay socket from VPN routing")
            }
            upstream.connect(InetSocketAddress(upstreamHost, upstreamPort), CONNECT_TIMEOUT_MS)
            upstream.sslParameters = upstream.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
            upstream.startHandshake()
            upstream.tcpNoDelay = true
            sockets += upstream

            thread(name = "APL-https-proxy-up", isDaemon = true) {
                try {
                    pump(local.getInputStream(), upstream.getOutputStream())
                } finally {
                    runCatching { upstream.shutdownOutput() }
                }
            }
            pump(upstream.getInputStream(), local.getOutputStream())
        } catch (_: Exception) {
            // tun2proxy observes a closed local connection and reports the session failure.
        } finally {
            upstreamForCleanup?.let {
                sockets -= it
                runCatching { it.close() }
            }
            sockets -= local
            runCatching { local.close() }
        }
    }

    private fun pump(input: InputStream, output: OutputStream) {
        val buffer = ByteArray(BUFFER_SIZE)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) return
            output.write(buffer, 0, count)
            output.flush()
        }
    }

    companion object {
        internal const val LOOPBACK_HOST = "127.0.0.1"
        private const val CONNECT_TIMEOUT_MS = 5000
        private const val BUFFER_SIZE = 32 * 1024
    }
}
