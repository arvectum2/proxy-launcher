package ru.arvectum.proxylauncher.routing

import java.net.InetAddress
import java.util.Locale

data class IpRoute(
    val address: InetAddress,
    val prefixLength: Int,
)

object SiteExclusionPolicy {
    const val MAX_ENTRIES = 32
    const val MAX_RESOLVED_ADDRESSES = 128
    const val MAX_ROUTES = 4096

    fun normalize(raw: String): String? {
        var value = raw.trim().lowercase(Locale.ROOT)
        if (value.isBlank()) return null

        value = value.substringBefore('#').trim()
        if (value.contains("://")) value = value.substringAfter("://")
        value = value.substringBefore('/').trim()
        if (value.isBlank()) return null

        if (value.startsWith("[")) {
            val end = value.indexOf(']')
            require(end > 1) { "Некорректный IPv6-адрес" }
            value = value.substring(1, end)
        } else if (value.count { it == ':' } == 1) {
            val host = value.substringBeforeLast(':')
            val port = value.substringAfterLast(':')
            if (port.isNotEmpty() && port.all(Char::isDigit)) value = host
        }

        value = value.trim()
        require(value.isNotBlank()) { "Введите домен или IP-адрес" }
        require('*' !in value && '?' !in value && !value.startsWith(".")) {
            "Маски и суффиксные правила пока не поддерживаются на Android; добавьте конкретный хост"
        }
        require(value.none(Char::isWhitespace)) { "Адрес не должен содержать пробелы" }
        require('@' !in value && '[' !in value && ']' !in value) { "Некорректный адрес" }
        require(value.length <= 253) { "Слишком длинный адрес" }
        return value
    }

    fun normalizeAll(rawEntries: Iterable<String>): List<String> {
        val normalized = linkedSetOf<String>()
        rawEntries.forEach { raw ->
            normalize(raw)?.let(normalized::add)
        }
        require(normalized.size <= MAX_ENTRIES) {
            "Можно сохранить не более $MAX_ENTRIES исключений"
        }
        return normalized.sorted()
    }

    fun complementRoutes(
        excluded: Collection<InetAddress>,
        addressBytes: Int,
    ): List<IpRoute> {
        require(addressBytes == IPV4_BYTES || addressBytes == IPV6_BYTES)
        val family = excluded
            .filter { it.address.size == addressBytes }
            .distinctBy { it.hostAddress }
        if (family.isEmpty()) {
            return listOf(IpRoute(InetAddress.getByAddress(ByteArray(addressBytes)), 0))
        }

        val root = TrieNode()
        family.forEach { addExcluded(root, it.address) }
        val routes = mutableListOf<IpRoute>()
        collectAllowed(root, 0, ByteArray(addressBytes), routes)
        require(routes.size <= MAX_ROUTES) {
            "Слишком много маршрутов для безопасного применения исключений"
        }
        return routes
    }

    private fun addExcluded(root: TrieNode, bytes: ByteArray) {
        var node = root
        for (depth in 0 until bytes.size * 8) {
            val one = bitAt(bytes, depth)
            node = if (one) {
                node.one ?: TrieNode().also { node.one = it }
            } else {
                node.zero ?: TrieNode().also { node.zero = it }
            }
        }
        node.excluded = true
    }

    private fun collectAllowed(
        node: TrieNode?,
        depth: Int,
        prefix: ByteArray,
        routes: MutableList<IpRoute>,
    ) {
        if (node == null) {
            routes += IpRoute(InetAddress.getByAddress(prefix), depth)
            return
        }
        if (node.excluded || depth == prefix.size * 8) return

        val zeroPrefix = prefix.copyOf()
        setBit(zeroPrefix, depth, false)
        collectAllowed(node.zero, depth + 1, zeroPrefix, routes)

        val onePrefix = prefix.copyOf()
        setBit(onePrefix, depth, true)
        collectAllowed(node.one, depth + 1, onePrefix, routes)
    }

    private fun bitAt(bytes: ByteArray, depth: Int): Boolean {
        val byteIndex = depth / 8
        val shift = 7 - (depth % 8)
        return ((bytes[byteIndex].toInt() ushr shift) and 1) == 1
    }

    private fun setBit(bytes: ByteArray, depth: Int, one: Boolean) {
        val byteIndex = depth / 8
        val shift = 7 - (depth % 8)
        val mask = 1 shl shift
        val current = bytes[byteIndex].toInt() and 0xff
        bytes[byteIndex] = if (one) {
            (current or mask).toByte()
        } else {
            (current and mask.inv()).toByte()
        }
    }

    private class TrieNode(
        var zero: TrieNode? = null,
        var one: TrieNode? = null,
        var excluded: Boolean = false,
    )

    private const val IPV4_BYTES = 4
    private const val IPV6_BYTES = 16
}
