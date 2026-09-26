package ru.arvectum.proxylauncher.routing

object ApplicationExclusionPolicy {
    const val MAX_ENTRIES = 128

    private val PACKAGE_NAME = Regex(
        "^[A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z][A-Za-z0-9_]*)+$",
    )

    fun normalize(packageName: String): String {
        val value = packageName.trim()
        require(value.length <= 255) { "Слишком длинное имя приложения" }
        require(PACKAGE_NAME.matches(value)) { "Некорректный идентификатор приложения" }
        return value
    }

    fun normalizeAll(packageNames: Collection<String>): List<String> {
        val normalized = packageNames
            .map(::normalize)
            .distinct()
            .sorted()
        require(normalized.size <= MAX_ENTRIES) {
            "Можно добавить не более $MAX_ENTRIES приложений"
        }
        return normalized
    }
}
