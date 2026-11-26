package ru.arvectum.proxylauncher.model

import java.util.Locale
import java.io.StringReader
import javax.xml.parsers.SAXParserFactory
import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.SAXException
import org.xml.sax.helpers.DefaultHandler

/** Bounded supplier formats. All invalid inputs fail closed without source text in errors. */
object ProxyStructuredImport {
    private val aliases = mapOf(
        "host" to setOf("host","hostname","ip","ipaddress","server","address","адрес","сервер"),
        "port" to setOf("port","порт"),
        "username" to setOf("username","user","login","логин","пользователь"),
        "password" to setOf("password","pass","passwd","pwd","пароль"),
        "type" to setOf("type","protocol","scheme","протокол","тип"),
        "name" to setOf("name","label","title","название","имя"),
    )
    private val columns = listOf("host","port","username","password","type","name")
    internal fun key(raw: String): String? {
        val clean = raw.trim().lowercase(Locale.ROOT).replace("_","").replace("-","").replace(" ","")
        return aliases.entries.firstOrNull { clean in it.value }?.key
    }
    internal fun invalid(): Nothing = throw IllegalArgumentException("Invalid structured proxy input")
    internal fun add(fields: MutableMap<String,String>, raw: String, value: String) {
        val k = key(raw) ?: invalid()
        if (fields.containsKey(k) || value.length > ProxyImport.MAX_INPUT) invalid()
        fields[k] = value
    }
    internal fun item(fields: Map<String,String>): ImportedProxy {
        val rawHost = fields["host"]?.trim() ?: invalid()
        val host = if (':' in rawHost && !rawHost.startsWith("[")) "[$rawHost]" else rawHost
        val type = when (fields["type"].orEmpty().trim().lowercase(Locale.ROOT)) {
            "", "http" -> ProxyType.HTTP
            "https" -> ProxyType.HTTPS
            "socks5","socks5h","socks" -> ProxyType.SOCKS5
            else -> invalid()
        }
        if (fields.values.any { v ->
            !Charsets.UTF_8.newEncoder().canEncode(v) ||
                v.any { it.isISOControl() || it == '\uFFFD' }
        }) invalid()
        return ProxyImport.item(host, fields["port"]?.trim() ?: invalid(), type,
            fields["username"].orEmpty(),fields["password"].orEmpty(),fields["name"].orEmpty()) ?: invalid()
    }

    internal fun looksLikeJson(text: String): Boolean =
        text.startsWith("{") || (text.startsWith("[") && text.drop(1).trimStart().firstOrNull() in listOf('{','"',']'))

    private fun checked(text: String): String {
        if (text.length > ProxyBatchImport.MAX_BYTES || !Charsets.UTF_8.newEncoder().canEncode(text) ||
            text.toByteArray(Charsets.UTF_8).size > ProxyBatchImport.MAX_BYTES) invalid()
        return text.trimStart().removePrefix("\uFEFF").trimStart()
    }

    fun json(text: String): List<ImportedProxy>? = attempt {
        StructuredJsonReader(checked(text)).parse()
    }

    private inline fun attempt(block: () -> List<ImportedProxy>): List<ImportedProxy>? =
        try { block().takeIf { it.size in 1..ProxyBatchImport.MAX_ENTRIES } }
        catch (_: Exception) { null }

    private fun firstLine(text: String) = text.substringBefore('\n').substringBefore('\r')
    private fun delimiter(text: String): Char? {
        val counts = linkedMapOf(',' to 0,';' to 0,'\t' to 0)
        var quoted = false
        for (c in firstLine(text)) {
            if (c == '"') quoted = !quoted
            else if (!quoted && c in counts) counts[c] = counts.getValue(c)+1
        }
        val max = counts.values.maxOrNull() ?: return null
        return counts.entries.singleOrNull { max > 0 && it.value == max }?.key
    }

    internal fun looksLikeCsv(text: String): Boolean {
        val first = firstLine(text)
        // Detect a candidate even if later syntax is invalid. No fallback after detection.
        return listOf(',', ';', '\t').any { sep ->
            val cells = first.split(sep).map { it.trim().trim('"') }
            cells.size >= 2 && ((cells.any { key(it) == "host" } && cells.any { key(it) == "port" }) ||
                cells[1].toIntOrNull() != null)
        }
    }

    fun csv(text: String): List<ImportedProxy>? = attempt {
        val clean = checked(text)
        val sep = delimiter(clean) ?: invalid()
        val rows = csvRows(clean, sep)
        val first = rows.firstOrNull() ?: invalid()
        val header = first.map(::key)
        val hasHeader = "host" in header && "port" in header
        val names = if (hasHeader) header.map { it ?: invalid() } else columns
        if (names.toSet().size != names.size) invalid()
        val records = if (hasHeader) rows.drop(1) else rows
        if (records.size !in 1..ProxyBatchImport.MAX_ENTRIES) invalid()
        records.map { cells ->
            if (cells.size !in 2..names.size || (hasHeader && cells.size != names.size)) invalid()
            item(names.zip(cells).toMap())
        }
    }

    private fun csvRows(text: String, sep: Char): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        val row = mutableListOf<String>()
        val cell = StringBuilder()
        var quoted = false
        var closed = false
        var atStart = true
        fun finishCell() {
            if (row.size >= columns.size) invalid()
            row.add(cell.toString())
            cell.setLength(0)
            atStart = true
            closed = false
        }
        fun finishRow() {
            finishCell()
            if (row.any { it.isNotBlank() }) {
                if (rows.size >= ProxyBatchImport.MAX_ENTRIES + 1) invalid()
                rows.add(row.toList())
            }
            row.clear()
        }
        var i = 0
        while (i < text.length) {
            val c = text[i++]
            if (quoted) {
                if (c == '"') {
                    if (text.getOrNull(i) == '"') { cell.append('"'); i++ }
                    else { quoted = false; closed = true }
                } else cell.append(c)
            } else when (c) {
                sep -> finishCell()
                '\r', '\n' -> {
                    finishRow()
                    if (c == '\r' && text.getOrNull(i) == '\n') i++
                }
                '"' -> { if (!atStart || closed) invalid(); quoted = true; atStart = false }
                else -> { if (closed) invalid(); cell.append(c); atStart = false }
            }
            if (cell.length > ProxyImport.MAX_INPUT) invalid()
        }
        if (quoted) invalid()
        if (row.isNotEmpty() || !atStart || cell.isNotEmpty()) finishRow()
        return rows
    }

    fun xml(text: String): List<ImportedProxy>? = attempt {
        val clean = checked(text)
        // A character stream precludes encoding tricks; reject declarations before parsing.
        if (clean.contains("<!DOCTYPE", ignoreCase = true) || clean.contains("<!ENTITY", ignoreCase = true)) invalid()
        val parser = SAXParserFactory.newInstance().apply {
            isNamespaceAware = false
            isValidating = false
        }.newSAXParser().xmlReader
        val handler = StructuredXmlReader()
        parser.contentHandler = handler
        parser.errorHandler = handler
        parser.entityResolver = org.xml.sax.EntityResolver { _, _ -> throw SAXException("External entity forbidden") }
        parser.parse(InputSource(StringReader(clean)))
        handler.items
    }

    /** Batch UI only. Legacy QR and TXT parsing stays separate. */
    fun parseBatch(text: String): List<ImportedProxy>? {
        val clean = try { checked(text) } catch (_: Exception) { return null }
        return when {
            clean.startsWith("<") -> xml(clean)
            looksLikeJson(clean) -> json(clean)
            looksLikeCsv(clean) -> ProxyBatchImport.parse(text) ?: csv(clean)
            else -> ProxyBatchImport.parse(text)
        }
    }
}

private class StructuredXmlReader : DefaultHandler() {
    val items = mutableListOf<ImportedProxy>()
    private var root: String? = null
    private var depth = 0
    private var fields: MutableMap<String,String>? = null
    private var field: String? = null
    private val content = StringBuilder()

    private fun startProxy(attributes: Attributes) {
        if (fields != null || items.size >= ProxyBatchImport.MAX_ENTRIES || attributes.length > 6)
            ProxyStructuredImport.invalid()
        fields = linkedMapOf<String,String>().apply {
            for (i in 0 until attributes.length) ProxyStructuredImport.add(this, attributes.getQName(i), attributes.getValue(i))
        }
    }
    override fun startElement(uri: String?, localName: String?, qName: String, attributes: Attributes) {
        val name = qName.lowercase(Locale.ROOT)
        depth++
        if (depth == 1) {
            root = name
            when (name) {
                "proxy" -> startProxy(attributes)
                "proxies" -> if (attributes.length != 0) ProxyStructuredImport.invalid()
                else -> ProxyStructuredImport.invalid()
            }
        } else if (depth == 2 && root == "proxies") {
            if (name != "proxy") ProxyStructuredImport.invalid()
            startProxy(attributes)
        } else {
            val proxyDepth = if (root == "proxy") 1 else 2
            if (depth != proxyDepth + 1 || fields == null || field != null ||
                attributes.length != 0 || ProxyStructuredImport.key(name) == null) ProxyStructuredImport.invalid()
            field = name
            content.setLength(0)
        }
    }
    override fun characters(ch: CharArray, start: Int, length: Int) {
        if (field != null) {
            if (content.length + length > ProxyImport.MAX_INPUT) ProxyStructuredImport.invalid()
            content.append(ch, start, length)
        } else if ((start until start + length).any { !ch[it].isWhitespace() }) ProxyStructuredImport.invalid()
    }
    override fun endElement(uri: String?, localName: String?, qName: String) {
        val name = qName.lowercase(Locale.ROOT)
        if (field != null) {
            if (field != name) ProxyStructuredImport.invalid()
            ProxyStructuredImport.add(fields ?: ProxyStructuredImport.invalid(), name, content.toString())
            field = null
            content.setLength(0)
        } else if (name == "proxy") {
            items.add(ProxyStructuredImport.item(fields ?: ProxyStructuredImport.invalid()))
            fields = null
        }
        depth--
    }
    override fun processingInstruction(target: String?, data: String?) { ProxyStructuredImport.invalid() }
    override fun error(e: org.xml.sax.SAXParseException) { throw e }
    override fun fatalError(e: org.xml.sax.SAXParseException) { throw e }
}
