package ru.arvectum.proxylauncher.model

/** Strict, non-recursive JSON grammar for proxy records; duplicate keys fail closed. */
internal class StructuredJsonReader(private val text: String) {
    private var i = 0
    private val items = mutableListOf<ImportedProxy>()
    private fun bad(): Nothing = ProxyStructuredImport.invalid()
    private fun ws() { while (text.getOrNull(i)?.let { it in " \t\r\n" } == true) i++ }
    private fun peek(): Char? { ws(); return text.getOrNull(i) }
    private fun take(c: Char): Boolean {
        if (peek() != c) return false
        i++
        return true
    }
    private fun expect(c: Char) { if (!take(c)) bad() }

    fun parse(): List<ImportedProxy> {
        when (peek()) {
            '[' -> array()
            '{' -> record(allowWrapper = true)
            else -> bad()
        }
        if (peek() != null || items.isEmpty()) bad()
        return items
    }
    private fun append(item: ImportedProxy) {
        if (items.size >= ProxyBatchImport.MAX_ENTRIES) bad()
        items.add(item)
    }
    private fun array() {
        expect('[')
        if (take(']')) bad()
        do {
            when (peek()) {
                '{' -> record(false)
                '"' -> {
                    val value = string()
                    if (value.any { it.isISOControl() }) bad()
                    append(ProxyImport.parse(value) ?: bad())
                }
                else -> bad()
            }
        } while (take(','))
        expect(']')
    }
    private fun record(allowWrapper: Boolean) {
        expect('{')
        val fields = linkedMapOf<String,String>()
        do {
            val key = string()
            expect(':')
            if (key == "proxies" && allowWrapper && fields.isEmpty()) {
                array()
                expect('}')
                return
            }
            val canonical = ProxyStructuredImport.key(key) ?: bad()
            val value = if (peek() == '"') string() else {
                if (canonical != "port") bad()
                portNumber()
            }
            ProxyStructuredImport.add(fields, key, value)
        } while (take(','))
        expect('}')
        append(ProxyStructuredImport.item(fields))
    }

    private fun portNumber(): String {
        ws()
        val start = i
        while (text.getOrNull(i)?.let { it in '0'..'9' } == true) i++
        val number = text.substring(start, i)
        if (number.isEmpty() || number.length > 5 || (number.length > 1 && number[0] == '0')) bad()
        return number
    }
    private fun string(): String {
        expect('"')
        val result = StringBuilder()
        while (true) {
            val c = text.getOrNull(i++) ?: bad()
            when (c) {
                '"' -> {
                    val value = result.toString()
                    if (!Charsets.UTF_8.newEncoder().canEncode(value)) bad()
                    return value
                }
                '\\' -> when (val e = text.getOrNull(i++) ?: bad()) {
                    '"','\\','/' -> result.append(e)
                    'b' -> result.append('\b')
                    'f' -> result.append('\u000c')
                    'n' -> result.append('\n')
                    'r' -> result.append('\r')
                    't' -> result.append('\t')
                    'u' -> {
                        if (i + 4 > text.length) bad()
                        var value = 0
                        repeat(4) {
                            val digit = text[i++]
                            val hex = when(digit) {
                                in '0'..'9' -> digit - '0'
                                in 'a'..'f' -> digit - 'a' + 10
                                in 'A'..'F' -> digit - 'A' + 10
                                else -> bad()
                            }
                            value = value * 16 + hex
                        }
                        result.append(value.toChar())
                    }
                    else -> bad()
                }
                else -> { if (c < ' ') bad(); result.append(c) }
            }
            if (result.length > ProxyImport.MAX_INPUT) bad()
        }
    }
}
