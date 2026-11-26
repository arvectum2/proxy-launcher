package ru.arvectum.proxylauncher.model

import org.junit.Assert.*
import org.junit.Test

class ProxyStructuredImportTest {
    private fun one(text: String): ImportedProxy = ProxyStructuredImport.parseBatch(text)!!.single()
    @Test fun jsonAliasesUnicodeAndExactPassword() {
        val p = one("""{"proxies":[{"server":"2001:db8::1","порт":1080,"login":"u+","pwd":" x:雪 ","protocol":"socks5h","title":"\u0410"}]}""")
        assertEquals("2001:db8::1",p.host)
        assertEquals(1080,p.port)
        assertEquals("u+",p.username)
        assertEquals(" x:雪 ",p.password)
        assertEquals("А",p.name)
        assertEquals(ProxyType.SOCKS5,p.type)
        assertEquals(2,ProxyStructuredImport.parseBatch("""["http://one.invalid:80",{"host":"two.invalid","port":"443","type":"https"}]""")!!.size)
    }
    @Test fun jsonInvalidAndAmbiguous() {
        for (s in listOf(
            """{"host":"a.invalid","host":"b.invalid","port":80}""",
            """{"host":"a.invalid","ip":"b.invalid","port":80}""",
            """{"host":"a.invalid","port":true}""",
            """{"host":"a.invalid","port":80.0}""",
            """{"host":"a.invalid","port":080}""",
            """{"host":"a.invalid","port":80,"password":null}""",
            """{"host":"a.invalid","port":80,"extra":{}}""",
            """{"proxies":[{"host":"a.invalid","port":80}],"other":1}""",
            """[{"host":"a.invalid","port":80}, {"host":"b.invalid","port":0}]""",
            """[{"host":"a.invalid","port":80},]""",
            """{"host":"a.invalid","port":80} garbage""",
            """{"host":"a.invalid","port":80,"name":"\ud800"}""",
            """{"host":"a.invalid","port":80,"type":"wireguard"}""",
            """[]""", """{}"""
        )) assertNull(ProxyStructuredImport.parseBatch(s))
    }
    @Test fun csvQuotedAndPositional() {
        val p = one("\uFEFFhost;port;login;pass;type;name\r\nproxy.invalid;443;u;\" a;\"\"b\";https;\"a,b\"\r\n")
        assertEquals(" a;\"b", p.password)
        assertEquals("a,b", p.name)
        assertEquals(ProxyType.HTTPS,p.type)
        val t = one("2001:db8::2\t1080\tu\t p \tsocks5\tname")
        assertEquals("2001:db8::2",t.host)
        assertEquals(" p ",t.password)
        assertEquals(ProxyType.HTTP,one("proxy.invalid,80").type)
        assertEquals("pass ",one("proxy.invalid,80,u,pass ").password)
    }
    @Test fun csvRejectMalformedAndDuplicateHeaders() {
        for (s in listOf("host,port,ip\na.invalid,80,b.invalid",
            "host,port,extra\na.invalid,80,x",
            "host,port,user\na.invalid,80",
            "a.invalid,80,u,\"unterminated",
            "a.invalid,80,u,\"a\"b",
            "a.invalid,80,u,p,socks4",
            "a.invalid,80\nb.invalid,0",
            "a.invalid,80,u,\"x\ny\"")) assertNull(ProxyStructuredImport.parseBatch(s))
    }
    @Test fun xmlAttributesAndLeaves() {
        val p = one("""<?xml version="1.0"?><proxies><proxy server="proxy.invalid" port="443" protocol="https"><login>u</login><password><![CDATA[ p:& ]]></password><title>A &amp; B</title></proxy></proxies>""")
        assertEquals(" p:& ",p.password)
        assertEquals("A & B",p.name)
        assertEquals(ProxyType.HTTPS,p.type)
        assertEquals("proxy.invalid",one("<proxy host='proxy.invalid' port='80'/>").host)
    }
    @Test fun xmlRejectsEntitiesNestingAndUnknown() {
        for (s in listOf(
            """<!DOCTYPE proxy SYSTEM "file:///nonexistent"><proxy host="a.invalid" port="80"/>""",
            """<!DOCTYPE proxy [<!ENTITY x SYSTEM "https://example.invalid/x">]><proxy host="&x;" port="80"/>""",
            """<proxy host="a.invalid" port="80"><ip>b.invalid</ip></proxy>""",
            """<proxy host="a.invalid" port="80"><password><nested/></password></proxy>""",
            """<proxy host="a.invalid" port="80" unknown="x"/>""",
            """<proxies><proxy host="a.invalid" port="80"/><proxy host="b.invalid" port="0"/></proxies>""",
            """<root><proxy host="a.invalid" port="80"/></root>""",
            """<proxy host="a.invalid" port="80">&undefined;</proxy>""",
            """<proxies/>"""
        )) assertNull(ProxyStructuredImport.parseBatch(s))
    }
    @Test fun limitsAndLegacyRouting() {
        val row = """{"host":"a.invalid","port":80}"""
        assertEquals(200,ProxyStructuredImport.parseBatch(List(200){row}.joinToString(",", "[", "]"))!!.size)
        assertNull(ProxyStructuredImport.parseBatch(List(201){row}.joinToString(",", "[", "]")))
        assertNull(ProxyStructuredImport.parseBatch(" ".repeat(256001)+row))
        assertNull(ProxyStructuredImport.parseBatch("雪".repeat(90000)))
        assertNull(ProxyStructuredImport.parseBatch("[".repeat(10000)))
        assertEquals("2001:db8::1",one("[2001:db8::1]:80").host)
        assertEquals("p,123",one("a.invalid:80:u:p,123").password)
        assertEquals(2,ProxyStructuredImport.parseBatch("# comment\nproxy.invalid:80\nhttps://other.invalid:443")!!.size)
    }
}
