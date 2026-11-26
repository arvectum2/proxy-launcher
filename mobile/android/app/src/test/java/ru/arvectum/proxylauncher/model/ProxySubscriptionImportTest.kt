package ru.arvectum.proxylauncher.model

import java.io.ByteArrayInputStream
import java.net.InetAddress
import java.net.UnknownHostException
import java.util.Base64
import org.junit.Assert.*
import org.junit.Test
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import ru.arvectum.proxylauncher.importing.ProxySubscriptionFetch

class ProxySubscriptionImportTest {
    @Test fun sourcePolicy() {
        val uri = ProxySubscriptionImport.source("https://supplier.example.com/list?token=fake%2Bvalue")!!
        assertEquals("token=fake%2Bvalue", uri.rawQuery)
        for (raw in listOf("http://supplier.com/list","https://127.0.0.1/","https://[::1]/",
            "https://localhost/","https://foo.local/","https://a.internal/","https://a.com:444/","https://a.com:/",
            "https://u:p@a.com/","https://a.com/#fragment","https://a.com./","https://a.com/\n",
            "https://a.com/"+"a".repeat(2048),"file:///tmp/list","https://a.com:443@b.com/"))
            assertNull(ProxySubscriptionImport.source(raw))
        assertNotNull(ProxySubscriptionImport.source("https://supplier.com:443/list"))
    }
    private fun address(raw: String) = InetAddress.getByName(raw)
    @Test fun routeAddressPolicy() {
        for (ip in listOf("0.0.0.0","10.1.2.3","127.0.0.1","100.64.0.1","169.254.169.254",
            "172.16.0.1","192.168.0.1","192.0.2.1","192.0.0.1","198.18.0.1","198.51.100.1",
            "203.0.113.1","224.0.0.1","255.255.255.255","::1","::","::ffff:127.0.0.1",
            "fc00::1","fe80::1","ff02::1","2001:db8::1","2002::1","64:ff9b::1","3fff::1"))
            assertFalse(ip,ProxySubscriptionImport.publicAddress(address(ip)))
        assertTrue(ProxySubscriptionImport.publicAddress(address("8.8.8.8")))
        assertTrue(ProxySubscriptionImport.publicAddress(address("2606:4700::1111")))
    }
    @Test fun actualDnsRouteFilter() {
        val good = address("8.8.8.8")
        assertEquals(listOf(good),ProxySubscriptionFetch.publicDns("supplier.com","supplier.com"){listOf(good)})
        for (bad in listOf(emptyList(), listOf(address("127.0.0.1")), listOf(good,address("10.0.0.1")))) {
            try { ProxySubscriptionFetch.publicDns("supplier.com","supplier.com"){bad}; fail("Accepted invalid route") }
            catch (_: UnknownHostException) {}
        }
        try { ProxySubscriptionFetch.publicDns("other.com","supplier.com"){fail("Unexpected lookup"); emptyList()}; fail("Host mismatch") }
        catch (_: UnknownHostException) {}
    }
    @Test fun plainAndBase64() {
        val plain = "https://demo:fake@proxy.invalid:443\n[2001:db8::1]:1080"
        val wrapped = Base64.getEncoder().encodeToString(plain.toByteArray())
        for (body in listOf(plain,wrapped,wrapped.chunked(8).joinToString("\r\n"))) {
            val items = ProxySubscriptionImport.decode(body.toByteArray())!!
            assertEquals(2,items.size)
            assertEquals("fake",items[0].password)
        }
        assertEquals(80,ProxySubscriptionImport.decode("""{"host":"a.invalid","port":80}""".toByteArray())!!.single().port)
        assertNull(ProxySubscriptionImport.decode("https://a.invalid:443\nvless://a.invalid:443".toByteArray()))
        assertNull(ProxySubscriptionImport.decode(Base64.getEncoder().encode("vless://a.invalid:443".toByteArray())))
        assertNull(ProxySubscriptionImport.decode(byteArrayOf(0xc0.toByte(),0xaf.toByte())))
        assertNull(ProxySubscriptionImport.decode(ByteArray(256001)))
        assertNull(ProxySubscriptionImport.decode(byteArrayOf(0)))
    }
    @Test fun responseStatusEncodingAndSource() {
        fun response(code: Int, url: String, encoding: String? = null, payload: String = "a.invalid:80"): Response =
            Response.Builder().request(Request.Builder().url(url).build()).protocol(Protocol.HTTP_1_1)
                .code(code).message("Synthetic").body(payload.toResponseBody()).apply {
                    if (encoding != null) header("Content-Encoding", encoding)
                }.build()
        val url = "https://supplier.com/list"
        response(200,url).use { assertEquals(80,ProxySubscriptionFetch.decodeResponse(it,"supplier.com"){false}!!.single().port) }
        for (r in listOf(response(302,url),response(401,url),response(200,"https://other.com/"),
            response(200,"http://supplier.com/"),response(200,url,"gzip"),response(200,url,payload="x".repeat(256001)))) {
            r.use { assertNull(ProxySubscriptionFetch.decodeResponse(it,"supplier.com"){false}) }
        }
        response(200,url).use { assertNull(ProxySubscriptionFetch.decodeResponse(it,"supplier.com"){true}) }
    }

    @Test fun boundedReadAndCancellation() {
        assertEquals(256000,ProxySubscriptionFetch.readBounded(ByteArrayInputStream(ByteArray(256000))){false}!!.size)
        assertNull(ProxySubscriptionFetch.readBounded(ByteArrayInputStream(ByteArray(256001))){false})
        assertNull(ProxySubscriptionFetch.readBounded(ByteArrayInputStream(byteArrayOf(1))){true})
        assertNull(ProxySubscriptionFetch.readBounded(ByteArrayInputStream(byteArrayOf())){false})
    }
}
