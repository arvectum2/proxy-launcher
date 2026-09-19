package ru.arvectum.proxylauncher.storage

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import ru.arvectum.proxylauncher.model.ProxyHealthSnapshot
import ru.arvectum.proxylauncher.model.ProxyHealthStatus
import ru.arvectum.proxylauncher.model.ProxyPoolEvent

/**
 * Default-process-only UI telemetry store.
 *
 * The VPN process never opens these preferences. Health/event updates are
 * relayed to the default process first, avoiding unsupported multi-process
 * SharedPreferences cache/write races.
 */
class PoolUiStateStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun setHealth(
        profileId: String,
        status: ProxyHealthStatus,
        latencyMs: Long?,
        checkedAtMs: Long = System.currentTimeMillis(),
    ) {
        val editor = prefs.edit()
            .putString(healthKey(profileId, "status"), status.name)
            .putLong(healthKey(profileId, "checked_at"), checkedAtMs)
        if (latencyMs == null) editor.remove(healthKey(profileId, "latency"))
        else editor.putLong(healthKey(profileId, "latency"), latencyMs.coerceAtLeast(0L))
        editor.apply()
    }

    fun getHealth(profileId: String): ProxyHealthSnapshot? {
        val statusName = prefs.getString(healthKey(profileId, "status"), null) ?: return null
        val status = runCatching { ProxyHealthStatus.valueOf(statusName) }
            .getOrDefault(ProxyHealthStatus.UNKNOWN)
        val latency = if (prefs.contains(healthKey(profileId, "latency"))) {
            prefs.getLong(healthKey(profileId, "latency"), 0L)
        } else {
            null
        }
        return ProxyHealthSnapshot(
            profileId = profileId,
            status = status,
            latencyMs = latency,
            checkedAtMs = prefs.getLong(healthKey(profileId, "checked_at"), 0L),
        )
    }

    fun removeHealth(profileId: String) {
        prefs.edit()
            .remove(healthKey(profileId, "status"))
            .remove(healthKey(profileId, "latency"))
            .remove(healthKey(profileId, "checked_at"))
            .apply()
    }
    fun appendEvent(
        type: String,
        profileId: String?,
        profileName: String?,
        detail: String?,
        timestampMs: Long,
    ) {
        val events = runCatching { JSONArray(prefs.getString(KEY_EVENTS, "[]")) }
            .getOrDefault(JSONArray())
        val item = JSONObject()
            .put("timestamp", timestampMs)
            .put("type", type.take(40))
            .put("profile_id", profileId ?: JSONObject.NULL)
            .put("profile_name", profileName?.take(80) ?: JSONObject.NULL)
            .put("detail", detail?.take(100) ?: JSONObject.NULL)
        val compact = JSONArray()
        val start = (events.length() - (MAX_EVENTS - 1)).coerceAtLeast(0)
        for (index in start until events.length()) {
            val existing = events.optJSONObject(index)
            if (existing != null) compact.put(existing)
        }
        compact.put(item)
        prefs.edit().putString(KEY_EVENTS, compact.toString()).apply()
    }

    fun listEvents(limit: Int = 20): List<ProxyPoolEvent> {
        val events = runCatching { JSONArray(prefs.getString(KEY_EVENTS, "[]")) }
            .getOrDefault(JSONArray())
        val start = (events.length() - limit.coerceIn(1, MAX_EVENTS)).coerceAtLeast(0)
        return (events.length() - 1 downTo start).mapNotNull { index ->
            events.optJSONObject(index)?.let { item ->
                ProxyPoolEvent(
                    timestampMs = item.optLong("timestamp", 0L),
                    type = item.optString("type", "event"),
                    profileId = item.optNullableString("profile_id"),
                    profileName = item.optNullableString("profile_name"),
                    detail = item.optNullableString("detail"),
                )
            }
        }
    }

    private fun JSONObject.optNullableString(key: String): String? =
        if (isNull(key)) null else optString(key).takeIf { it.isNotBlank() }

    private fun healthKey(id: String, field: String) = "health.$id.$field"

    companion object {
        private const val PREFS_NAME = "apl_mobile_pool_ui_v1"
        private const val KEY_EVENTS = "events_v1"
        private const val MAX_EVENTS = 40
    }
}
