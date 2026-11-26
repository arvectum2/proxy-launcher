package ru.arvectum.proxylauncher.model

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream

class ProxyBatchImportTest {
    @Test fun acceptsBomCrLfAndComments() {
        val items = ProxyBatchImport.parse("\uFEFF\r\n# list\r\nproxy.invalid:80\r\nsocks5://[2001:db8::1]:1080\n")!!
        assertEquals(2, items.size)
        assertEquals(ProxyType.SOCKS5, items[1].type)
    }

    @Test fun rejectsWholeListAndBounds() {
        for (text in listOf("", "# only", "proxy.invalid:80\ninvalid", "proxy.invalid:80\nvless://host:443",
            "proxy.invalid:80\n".repeat(201), "x".repeat(256001), "# " + "é".repeat(128001) + "\nproxy.invalid:80",
            "proxy.invalid:80\n\uD800")) assertNull(ProxyBatchImport.parse(text))
        assertEquals(200, ProxyBatchImport.parse("proxy.invalid:80\n".repeat(200))!!.size)
    }

    @Test fun strictBoundedStream() {
        assertEquals("proxy.invalid:80", ProxyBatchImport.readText("proxy.invalid:80".byteInputStream()))
        assertNull(ProxyBatchImport.readText(ByteArrayInputStream(byteArrayOf(0xc3.toByte(), 0x28))))
        assertNull(ProxyBatchImport.readText(ByteArrayInputStream(ByteArray(256001))))
        assertEquals(256000, ProxyBatchImport.readText(ByteArrayInputStream(ByteArray(256000) { 65 }))!!.length)
    }

    @Test fun dedupePreservesExistingAndFirstOccurrence() {
        val existing = listOf(ProxyProfile("old","old","PROXY.invalid",80,ProxyType.HTTP,"demo"))
        val items = ProxyBatchImport.parse("http://demo:old@proxy.invalid:80\nhttp://demo:new@proxy.invalid:80\n" +
            "http://other:first@proxy.invalid:80\nhttp://other:second@PROXY.invalid:80\nhttps://proxy.invalid:80")!!
        val preview = ProxyBatchImport.preview(items, existing)
        assertEquals(3, preview.skipped)
        assertEquals(2, preview.items.size)
        assertEquals("first", preview.items.first().password)
        assertFalse(preview.toString().contains("first"))
        assertEquals(ProxyType.HTTPS, preview.items.last().type)
    }
}
