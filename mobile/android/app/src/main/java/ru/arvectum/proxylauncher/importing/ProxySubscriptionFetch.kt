package ru.arvectum.proxylauncher.importing

import java.net.InetAddress
import java.net.Proxy
import java.net.UnknownHostException
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.concurrent.TimeUnit
import okhttp3.Authenticator
import okhttp3.Call
import okhttp3.CookieJar
import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import ru.arvectum.proxylauncher.model.ImportedProxy
import ru.arvectum.proxylauncher.model.ProxyBatchImport
import ru.arvectum.proxylauncher.model.ProxySubscriptionImport

/** A single user-triggered, cancelable request. No persistent client/cache or credentials. */
class ProxySubscriptionFetch(raw: String) {
    private val source = requireNotNull(ProxySubscriptionImport.source(raw)) { "Invalid subscription source" }
    private val client = OkHttpClient.Builder()
        .dns(object : Dns { override fun lookup(hostname: String) = publicDns(hostname, source.host) })
        .proxy(Proxy.NO_PROXY)
        .followRedirects(false)
        .followSslRedirects(false)
        .retryOnConnectionFailure(false)
        .cookieJar(CookieJar.NO_COOKIES)
        .authenticator(Authenticator.NONE)
        .proxyAuthenticator(Authenticator.NONE)
        .cache(null)
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .callTimeout(25, TimeUnit.SECONDS)
        .build()
    private val call: Call = client.newCall(Request.Builder().url(source.toASCIIString())
        .header("Accept", "text/plain, text/csv, application/json, application/xml, application/octet-stream")
        .header("Accept-Encoding", "identity")
        .header("Cache-Control", "no-store")
        .get().build())

    fun cancel() { call.cancel() }

    fun load(): List<ImportedProxy>? = try {
        call.execute().use { response -> decodeResponse(response, source.host) { call.isCanceled() } }
    } catch (_: Exception) { null }
    finally { client.connectionPool.evictAll(); client.dispatcher.executorService.shutdown() }

    companion object {
        internal fun decodeResponse(response: Response, expected: String, canceled: () -> Boolean): List<ImportedProxy>? {
            val body = response.body ?: return null
            if (canceled() || response.code != 200 || !response.request.url.host.equals(expected, true) ||
                response.request.url.scheme != "https" ||
                response.header("Content-Encoding")?.equals("identity", true) == false ||
                body.contentLength() > ProxyBatchImport.MAX_BYTES) return null
            val bytes = readBounded(body.byteStream(), canceled) ?: return null
            return try { if (canceled()) null else ProxySubscriptionImport.decode(bytes) }
            finally { bytes.fill(0) }
        }

        internal fun publicDns(host: String, expected: String,
                               resolve: (String) -> List<InetAddress> = Dns.SYSTEM::lookup): List<InetAddress> {
            if (!host.equals(expected, true)) throw UnknownHostException("Subscription host mismatch")
            val addresses = resolve(host)
            if (addresses.isEmpty() || addresses.any { !ProxySubscriptionImport.publicAddress(it) })
                throw UnknownHostException("Subscription address rejected")
            return addresses
        }

        internal fun readBounded(stream: InputStream, canceled: () -> Boolean): ByteArray? {
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            return try {
                while (!canceled()) {
                    val n = stream.read(buffer, 0, minOf(buffer.size, ProxyBatchImport.MAX_BYTES + 1 - out.size()))
                    if (n < 0) return out.toByteArray().takeIf { it.isNotEmpty() }
                    if (n == 0 || out.size() + n > ProxyBatchImport.MAX_BYTES) return null
                    out.write(buffer, 0, n)
                }
                null
            } catch (_: Exception) { null }
            finally { buffer.fill(0) }
        }
    }
}
