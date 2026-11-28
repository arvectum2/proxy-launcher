package ru.arvectum.proxylauncher.storage

import java.io.ByteArrayOutputStream
import java.io.StringReader
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.BasicFileAttributes
import javax.xml.parsers.SAXParserFactory
import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.SAXException
import org.xml.sax.helpers.DefaultHandler

/**
 * Reads Android's SharedPreferences XML directly, never via the process cache.
 * Caller MUST hold the common process gate and exclude all preference writers.
 * Unknown formats, backup files and ambiguous reads fail closed.
 */
internal class ManagedPreferenceDiskVerifier(
    private val file: Path,
    private val syncDirectory: (Path) -> Unit = { dir ->
        FileChannel.open(dir,StandardOpenOption.READ).use { it.force(true) }
    },
) {
    fun matches(expected: Map<String,Any>): Boolean =
        runCatching { readVerified() == expected }.getOrDefault(false)

    fun readVerified(): Map<String,Any> {
        val parent = requireNotNull(file.parent)
        val backup = parent.resolve(file.fileName.toString()+".bak")
        require(Files.isDirectory(parent,LinkOption.NOFOLLOW_LINKS) &&
            Files.notExists(backup,LinkOption.NOFOLLOW_LINKS))
        val before = attributes()
        require(before.isRegularFile && before.size() in 1..MAX_BYTES.toLong())
        val out = ByteArrayOutputStream()
        FileChannel.open(file,StandardOpenOption.READ,StandardOpenOption.WRITE,LinkOption.NOFOLLOW_LINKS).use { channel ->
            require(channel.size() == before.size())
            channel.force(true)
            val buffer = ByteBuffer.allocate(8192)
            try {
                while (true) {
                    buffer.clear()
                    val count = channel.read(buffer)
                    if (count < 0) break
                    require(count > 0 && count <= MAX_BYTES-out.size())
                    out.write(buffer.array(),0,count)
                }
            } finally { buffer.array().fill(0) }
            require(out.size().toLong() == before.size() && channel.size() == before.size())
        }
        syncDirectory(parent)
        val after = attributes()
        require(after.isRegularFile && before.fileKey() == after.fileKey() &&
            before.size() == after.size() && before.lastModifiedTime() == after.lastModifiedTime() &&
            Files.notExists(backup,LinkOption.NOFOLLOW_LINKS))
        val bytes=out.toByteArray()
        return try {
            val text=Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes)).toString()
            require(!text.contains("<!DOCTYPE",ignoreCase=true) && !text.contains("<!ENTITY",ignoreCase=true))
            val handler=PreferenceXml()
            val parser=SAXParserFactory.newInstance().apply {
                isNamespaceAware=false
                isValidating=false
            }.newSAXParser().xmlReader
            parser.contentHandler=handler
            parser.errorHandler=handler
            parser.entityResolver=org.xml.sax.EntityResolver { _,_ -> throw SAXException("External entity forbidden") }
            parser.parse(InputSource(StringReader(text.removePrefix("\uFEFF"))))
            handler.result()
        } finally { bytes.fill(0) }
    }

    private fun attributes() = Files.readAttributes(file,BasicFileAttributes::class.java,LinkOption.NOFOLLOW_LINKS)

    companion object { const val MAX_BYTES=16_777_216; const val MAX_KEYS=24_000 }
}

/** Exact primitive map/set subset written by Android SharedPreferences. */
private class PreferenceXml : DefaultHandler() {
    private val entries=linkedMapOf<String,Any>()
    private var depth=0
    private var seenRoot=false
    private var closedRoot=false
    private var name:String?=null
    private var tag:String?=null
    private var scalar:Any?=null
    private var set:MutableSet<String>?=null
    private var text=StringBuilder()
    private fun bad():Nothing=throw SAXException("Invalid preference XML")
    private fun requireAttrs(a:Attributes,vararg names:String) {
        if (a.length!=names.size || names.any { a.getIndex(it)<0 }) bad()
    }
    override fun startElement(uri:String?,localName:String?,qName:String,a:Attributes) {
        depth++
        when(depth) {
            1 -> {
                if(seenRoot || qName!="map") bad()
                requireAttrs(a)
                seenRoot=true
            }
            2 -> {
                if(!seenRoot || closedRoot || entries.size>=ManagedPreferenceDiskVerifier.MAX_KEYS) bad()
                val key=a.getValue("name") ?: bad()
                if(key.isEmpty() || entries.containsKey(key)) bad()
                name=key;tag=qName;text=StringBuilder()
                when(qName) {
                    "string" -> requireAttrs(a,"name")
                    "set" -> { requireAttrs(a,"name");set=linkedSetOf() }
                    "int","long","float","boolean" -> {
                        requireAttrs(a,"name","value")
                        val value=a.getValue("value")
                        scalar=when(qName) {
                            "int" -> value.toIntOrNull() ?: bad()
                            "long" -> value.toLongOrNull() ?: bad()
                            "float" -> value.toFloatOrNull()?.takeIf { it.isFinite() } ?: bad()
                            else -> when(value) { "true" -> true; "false" -> false; else -> bad() }
                        }
                    }
                    else -> bad()
                }
            }
            3 -> {
                if(tag!="set" || qName!="string") bad()
                requireAttrs(a);text=StringBuilder()
            }
            else -> bad()
        }
    }
    override fun characters(ch:CharArray,start:Int,length:Int) {
        if(depth==2 && tag=="string" || depth==3 && tag=="set") text.append(ch,start,length)
        else if((start until start+length).any{ch[it] !in " \t\r\n"}) bad()
    }
    override fun endElement(uri:String?,localName:String?,qName:String) {
        when(depth) {
            3 -> {
                val current=set ?: bad()
                if(qName!="string" || current.size>=ManagedPreferenceDiskVerifier.MAX_KEYS || !current.add(text.toString())) bad()
                text=StringBuilder()
            }
            2 -> {
                if(qName!=tag) bad()
                val value=when(tag) { "string" -> text.toString(); "set" -> set?.toSet() ?: bad(); else -> scalar ?: bad() }
                entries[name ?: bad()]=value
                name=null;tag=null;scalar=null;set=null;text=StringBuilder()
            }
            1 -> { if(qName!="map") bad();closedRoot=true }
            else -> bad()
        }
        depth--
    }
    override fun processingInstruction(target:String?,data:String?) { bad() }
    override fun error(e:org.xml.sax.SAXParseException) { throw e }
    override fun fatalError(e:org.xml.sax.SAXParseException) { throw e }
    fun result():Map<String,Any> {
        if(!seenRoot || !closedRoot || depth!=0) bad()
        return entries.toMap()
    }
}
