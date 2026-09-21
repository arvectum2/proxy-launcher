package ru.arvectum.proxylauncher.gateway

import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType

data class FreeProxyLocation(
    val id: String,
    val label: String,
    val countryCode: String,
    val available: Boolean? = null,
    val latencyMs: Long? = null,
)

data class FreeProxySession(
    val profile: ProxyProfile,
    val password: String,
    val expiresAtEpochSeconds: Long,
)

class FreeGatewayClient(
    private val baseUrl: String = DEFAULT_BASE_URL,
) {
    fun listLocations(): List<FreeProxyLocation> =
        FreeGatewayJson.parseLocations(request("GET", "/v1/free/locations"))

    fun createSession(locationId: String, displayName: String): FreeProxySession {
        require(locationId.isNotBlank()) { "Free proxy location id is required" }
        val payload = JSONObject().put("location_id", locationId).toString()
        return FreeGatewayJson.parseSession(
            request("POST", "/v1/free/session", payload),
            locationId,
            displayName,
        )
    }

    private fun request(method: String, path: String, body: String? = null): String {
        val connection = URL(baseUrl.trimEnd('/') + path).openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = method
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("User-Agent", "Arvectum-Proxy-Launcher-Android")
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val response = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                throw IllegalStateException("Gateway returned HTTP $status")
            }
            response
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        const val DEFAULT_BASE_URL = "https://mac-mini-master.tail786c4b.ts.net"

        val BOOTSTRAP_LOCATIONS = listOf(
            FreeProxyLocation("ru-free", "РФ", "RU"),
            FreeProxyLocation("us-free", "США", "US"),
        )
        private const val CONNECT_TIMEOUT_MS = 8_000
        private const val READ_TIMEOUT_MS = 8_000
    }
}

internal object FreeGatewayJson {
    fun parseLocations(body: String): List<FreeProxyLocation> {
        val array = JSONObject(body).getJSONArray("locations")
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                val location = FreeProxyLocation(
                    id = item.getString("id"),
                    label = item.getString("label"),
                    countryCode = item.getString("country_code"),
                    available = if (item.has("available")) item.getBoolean("available") else null,
                    latencyMs = if (item.has("latency_ms") && !item.isNull("latency_ms")) {
                        item.getLong("latency_ms")
                    } else {
                        null
                    },
                )
                require(location.id.isNotBlank() && location.label.isNotBlank()) {
                    "Gateway returned an invalid free proxy location"
                }
                add(location)
            }
        }
    }

    fun parseSession(
        body: String,
        locationId: String,
        displayName: String,
    ): FreeProxySession {
        val root = JSONObject(body)
        val proxy = root.getJSONObject("proxy")
        val host = proxy.getString("host")
        val port = proxy.getInt("port")
        val username = proxy.getString("username")
        val password = proxy.getString("password")
        val type = runCatching {
            ProxyType.valueOf(proxy.getString("type").uppercase())
        }.getOrElse {
            throw IllegalArgumentException("Gateway returned an unsupported proxy type")
        }
        require(host.isNotBlank() && port in 1..65535 && username.isNotBlank() && password.isNotBlank()) {
            "Gateway returned an invalid proxy session"
        }
        val expiresAt = root.getLong("expires_at")
        require(expiresAt > 0L) { "Gateway returned an invalid session expiry" }
        return FreeProxySession(
            profile = ProxyProfile(
                id = "free:$locationId",
                name = displayName,
                host = host,
                port = port,
                type = type,
                username = username,
            ),
            password = password,
            expiresAtEpochSeconds = expiresAt,
        )
    }
}

object FreeSessionRefreshPolicy {
    fun delayMillis(nowEpochSeconds: Long, expiresAtEpochSeconds: Long): Long {
        val remainingSeconds = (expiresAtEpochSeconds - nowEpochSeconds).coerceAtLeast(0L)
        val marginSeconds = (remainingSeconds / 10L).coerceIn(MIN_MARGIN_SECONDS, MAX_MARGIN_SECONDS)
        return ((remainingSeconds - marginSeconds) * 1_000L).coerceAtLeast(MIN_DELAY_MS)
    }

    private const val MIN_MARGIN_SECONDS = 30L
    private const val MAX_MARGIN_SECONDS = 300L
    private const val MIN_DELAY_MS = 1_000L
}
