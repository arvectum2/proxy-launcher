package ru.arvectum.proxylauncher.model

import org.junit.Assert.*
import org.junit.Test

class ProxyImportTest {
    @Test fun supplierAndCredentials() {
        val plain = ProxyImport.parse("proxy.invalid:8080")!!
        assertEquals("proxy.invalid", plain.host)
        assertEquals(8080, plain.port)
        assertEquals(ProxyType.HTTP, plain.type)
        val auth = ProxyImport.parse("proxy.invalid:1080:demo:p:a:ss")!!
        assertEquals("demo", auth.username)
        assertEquals("p:a:ss", auth.password)
        assertEquals("ImportedProxy(<redacted>)", auth.toString())
    }

    @Test fun uriTypesAndEscaping() {
        val item = ProxyImport.parse("HTTPS://demo:p%40ss%2B%3A@proxy.invalid:443/#Example")!!
        assertEquals(ProxyType.HTTPS, item.type)
        assertEquals("p@ss+:", item.password)
        assertEquals("Example", item.name)
        assertEquals(ProxyType.SOCKS5, ProxyImport.parse("socks5h://proxy.invalid:1080")!!.type)
        assertEquals(ProxyType.SOCKS5, ProxyImport.parse("socks://proxy.invalid:1080")!!.type)
        assertEquals("a+b", ProxyImport.parse("http://demo:a+b@proxy.invalid:80")!!.password)
    }

    @Test fun ipv6AndBom() {
        assertEquals("2001:db8::1", ProxyImport.parse("[2001:db8::1]:1080")!!.host)
        assertEquals("2001:db8::1", ProxyImport.parse("socks5://[2001:db8::1]:1080")!!.host)
        assertEquals("proxy.invalid", ProxyImport.parse("\uFEFF  proxy.invalid:8080 ")!!.host)
    }

    @Test fun malformedAndUnsupportedRejected() {
        for (text in listOf("", "proxy.invalid", "proxy.invalid:0", "proxy.invalid:65536",
            "proxy.invalid:-1", "proxy.invalid:1:demo", "proxy.invalid:1::password",
            "http://proxy.invalid", "http://proxy.invalid:80/path", "http://proxy.invalid:80?q=x",
            "vless://proxy.invalid:443", "file:///tmp/foo", "http://demo%3Auser:secret@proxy.invalid:80",
            "http://demo:%0A@proxy.invalid:80", "http://demo:%FF@proxy.invalid:80",
            "http://demo:%XX@proxy.invalid:80", "http://proxy.invalid:80\nother.invalid:81",
            "[not-ipv6]:1080", "2001:db8::1:1080", "host/path:80", "host@other:80",
            "http://[fe80::1%25en0]:80", "x".repeat(ProxyImport.MAX_INPUT + 1))) {
            assertNull(ProxyImport.parse(text))
        }
    }
}
