package ru.arvectum.proxylauncher.tunnel

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.SystemClock
import ru.arvectum.proxylauncher.MainActivity
import ru.arvectum.proxylauncher.model.PrimaryRestorePolicy
import ru.arvectum.proxylauncher.model.ProxyHealthStatus
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType
import ru.arvectum.proxylauncher.storage.ResolvedProxyProfile
import ru.arvectum.proxylauncher.storage.SecureProfileStore

/**
 * Runs in :vpn, deliberately isolated from the UI process.
 *
 * tun2proxy v0.8.3 calls process::exit(-1) two seconds after its native runtime
 * returns. Keeping the engine in a dedicated process prevents that upstream CLI
 * shutdown safeguard from killing the application UI.
 *
 * Blocking proxy preflight is deliberately kept off the Android main thread.
 */
class ProxyVpnService : VpnService() {
    private val lock = Any()
    private val engine: ProxyEngineAdapter = Tun2ProxyEngineAdapter()
    private val probe = ProxyProtocolProbe()
    private val failoverPolicy = FailoverPolicy()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var store: SecureProfileStore
    private var tunFd: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var preflightWorker: Thread? = null
    private var monitorWorker: Thread? = null
    private var activePrepared: PreparedProxy? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var sessionGeneration: Long = 0
    @Volatile private var stopping = false
    @Volatile private var failoverHandoff = false
    @Volatile private var lastNetworkTransitionElapsedMs = 0L

    override fun onCreate() {
        super.onCreate()
        store = SecureProfileStore(this)
        ensureNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_DISCONNECT) {
            stopTunnel()
            return START_NOT_STICKY
        }
        startTunnel()
        return START_STICKY
    }

    override fun onRevoke() {
        stopTunnel()
    }

    override fun onDestroy() {
        stopAutoMonitor()
        if (!stopping) shutdownEngineSilently()
        super.onDestroy()
    }

    private fun startTunnel() {
        val generation = synchronized(lock) {
            if (worker?.isAlive == true || preflightWorker?.isAlive == true || tunFd != null) return
            stopping = false
            failoverHandoff = false
            activePrepared = null
            sessionGeneration += 1
            sessionGeneration
        }

        startForegroundCompat("Проверяем прокси…")
        publishState(STATE_CONNECTING, "Проверяем прокси…")

        val thread = Thread({
            val prepared = try {
                resolveProxySelection(generation)
            } catch (e: ProxyProbeException) {
                failStartFromWorker(generation, e.message ?: "Прокси недоступен")
                return@Thread
            } catch (e: IllegalStateException) {
                failStartFromWorker(generation, e.message ?: "Внутренняя ошибка проверки прокси")
                return@Thread
            } catch (_: Exception) {
                failStartFromWorker(generation, "Не удалось проверить сохранённые прокси")
                return@Thread
            }

            mainHandler.post {
                continueStartAfterPreflight(generation, prepared)
            }
        }, "APL-proxy-preflight")

        synchronized(lock) {
            if (generation != sessionGeneration || stopping) return
            preflightWorker = thread
        }
        thread.start()
    }

    private fun continueStartAfterPreflight(
        generation: Long,
        prepared: PreparedProxy,
    ) {
        val resolved = prepared.resolved
        val selectedProfile = prepared.selectedProfile
        val selectionLabel = if (prepared.autoSelection) {
            "Авто → ${resolved.profile.name}"
        } else {
            resolved.profile.name
        }

        synchronized(lock) {
            if (generation != sessionGeneration || stopping) return
            preflightWorker = null
        }

        publishState(
            STATE_CONNECTING,
            "$selectionLabel · ${protocolLabel(selectedProfile.type)}. Создаём VPN…",
        )

        val tun = try {
            val builder = Builder()
                .setSession("Arvectum Proxy Launcher")
                .setBlocking(false)
                .setMtu(Tun2ProxyEngineAdapter.TUN_MTU)
                .addAddress("10.111.0.1", 32)
                .addRoute("0.0.0.0", 0)
                .addAddress("fd00:111::1", 128)
                .addRoute("::", 0)
                .addDnsServer("198.18.0.1")

            builder.addDisallowedApplication(packageName)
            builder.establish() ?: error("VpnService.Builder.establish() returned null")
        } catch (_: Exception) {
            failStartForSession(generation, "Android не смог создать VPN-интерфейс")
            return
        }

        synchronized(lock) {
            if (generation != sessionGeneration || stopping) {
                tun.runCatching { close() }
                return
            }
            tunFd = tun
        }

        val thread = Thread({
            val result = try {
                engine.run(tun, selectedProfile, resolved.password)
            } catch (_: Throwable) {
                ENGINE_START_FAILURE
            }
            onEngineExit(generation, result)
        }, "APL-tun2proxy")
        synchronized(lock) {
            if (generation != sessionGeneration || stopping) {
                tun.runCatching { close() }
                tunFd = null
                return
            }
            worker = thread
        }
        thread.start()

        mainHandler.postDelayed({
            val running = synchronized(lock) {
                generation == sessionGeneration &&
                    worker === thread &&
                    thread.isAlive &&
                    !stopping
            }
            if (running) {
                synchronized(lock) { activePrepared = prepared }
                val label = protocolLabel(selectedProfile.type)
                startForegroundCompat("Подключено · $selectionLabel")
                publishState(
                    STATE_CONNECTED,
                    "Подключено · $selectionLabel · $label · ${resolved.profile.host}:${resolved.profile.port}",
                )
                if (prepared.autoSelection) {
                    startAutoMonitor(generation, prepared)
                }
            }
        }, CONNECT_CONFIRM_DELAY_MS)
    }

    private fun resolveProxySelection(generation: Long): PreparedProxy {
        if (!store.isAutoProfileSelection()) {
            val resolved = store.loadActive()
                ?: throw ProxyProbeException("Сначала добавьте прокси")
            publishHealth(resolved.profile.id, ProxyHealthStatus.CHECKING, null)
            val measured = try {
                probe.resolveMeasured(resolved.profile, resolved.password) { candidate ->
                    mainHandler.post {
                        publishPreflightProgress(
                            generation = generation,
                            profileName = resolved.profile.name,
                            type = candidate,
                            autoSelection = false,
                        )
                    }
                }
            } catch (e: Exception) {
                publishHealth(resolved.profile.id, ProxyHealthStatus.UNAVAILABLE, null)
                throw e
            }
            publishHealth(resolved.profile.id, ProxyHealthStatus.AVAILABLE, measured.latencyMs)
            return PreparedProxy(resolved, measured.profile, autoSelection = false, measured.latencyMs)
        }

        val profiles = store.listProfiles()
        if (profiles.isEmpty()) throw ProxyProbeException("Нет сохранённых прокси для режима Авто")

        val now = System.currentTimeMillis()
        val recentlyFailedId = store.getRecentlyFailedProfileId()?.takeIf {
            failoverPolicy.recentlyFailedStillSuppressed(now, store.getRecentlyFailedAtMs())
        }
        val byId = profiles.associateBy { it.id }
        val ordered = failoverPolicy.orderCandidates(
            profileIds = profiles.map { it.id },
            primaryId = store.getPrimaryProfileId(),
            lastSuccessfulId = store.getLastAutoProfileId(),
            recentlyFailedId = recentlyFailedId,
        ).mapNotNull(byId::get)
        val failures = mutableListOf<String>()

        for (profile in ordered) {
            mainHandler.post { publishAutoProfileProgress(generation, profile.name) }
            val resolved = runCatching { store.loadProfile(profile.id) }.getOrNull()
            if (resolved == null) {
                failures += "${profile.name}: не удалось прочитать профиль"
                continue
            }

            publishHealth(profile.id, ProxyHealthStatus.CHECKING, null)
            try {
                val measured = probe.resolveMeasured(resolved.profile, resolved.password) { candidate ->
                    mainHandler.post {
                        publishPreflightProgress(
                            generation = generation,
                            profileName = resolved.profile.name,
                            type = candidate,
                            autoSelection = true,
                        )
                    }
                }
                publishHealth(profile.id, ProxyHealthStatus.AVAILABLE, measured.latencyMs)
                runCatching { store.setLastAutoProfileId(profile.id) }
                val failedId = store.getRecentlyFailedProfileId()
                if (failedId != null && failedId != profile.id &&
                    now - store.getLastFailoverAtMs() <= SWITCH_EVENT_WINDOW_MS
                ) {
                    publishPoolEvent("switched", profile.id, profile.name, "Auto fallback")
                }
                return PreparedProxy(resolved, measured.profile, autoSelection = true, measured.latencyMs)
            } catch (e: ProxyProbeException) {
                publishHealth(profile.id, ProxyHealthStatus.UNAVAILABLE, null)
                failures += "${profile.name}: ${e.message ?: "недоступен"}"
            } catch (e: Exception) {
                publishHealth(profile.id, ProxyHealthStatus.UNAVAILABLE, null)
                failures += "${profile.name}: ${e.message?.take(80) ?: "ошибка проверки"}"
            }
        }

        val detail = failures.joinToString("; ").take(MAX_AUTO_ERROR_LENGTH)
        throw ProxyProbeException(
            if (detail.isBlank()) "Нет рабочего сохранённого прокси"
            else "Нет рабочего прокси. $detail",
        )
    }

    private fun publishAutoProfileProgress(generation: Long, profileName: String) {
        val active = synchronized(lock) {
            generation == sessionGeneration && !stopping
        }
        if (!active) return
        publishState(STATE_CONNECTING, "Авто: проверяем $profileName…")
    }

    private fun publishPreflightProgress(
        generation: Long,
        profileName: String,
        type: ProxyType,
        autoSelection: Boolean,
    ) {
        val active = synchronized(lock) {
            generation == sessionGeneration && !stopping
        }
        if (!active) return
        val prefix = if (autoSelection) "Авто: $profileName" else profileName
        publishState(STATE_CONNECTING, "$prefix · ${protocolLabel(type)}…")
    }

    private fun startAutoMonitor(generation: Long, prepared: PreparedProxy) {
        stopAutoMonitor()
        registerNetworkCallback()
        val thread = Thread({
            var consecutiveFailures = 0
            var lastSecondaryScanElapsed = 0L
            var backupCursor = 0

            while (isSessionActive(generation)) {
                try {
                    Thread.sleep(failoverPolicy.tuning.healthIntervalMs)
                } catch (_: InterruptedException) {
                    return@Thread
                }
                if (!isSessionActive(generation)) return@Thread

                if (!failoverPolicy.networkSettled(
                        SystemClock.elapsedRealtime(),
                        lastNetworkTransitionElapsedMs,
                    )
                ) continue

                val current = synchronized(lock) { activePrepared } ?: prepared
                val profileId = current.resolved.profile.id
                publishHealth(profileId, ProxyHealthStatus.CHECKING, null)

                val measured = try {
                    probe.resolveMeasured(current.selectedProfile, current.resolved.password)
                } catch (_: Exception) {
                    null
                }

                if (measured == null) {
                    consecutiveFailures += 1
                    publishHealth(profileId, ProxyHealthStatus.UNAVAILABLE, null)
                    if (failoverPolicy.failureConfirmed(consecutiveFailures) &&
                        failoverPolicy.cooldownElapsed(
                            System.currentTimeMillis(),
                            store.getLastFailoverAtMs(),
                        )
                    ) {
                        mainHandler.post {
                            requestAutoHandoff(generation, current, restorationProfile = null)
                        }
                        return@Thread
                    }
                    continue
                }

                consecutiveFailures = 0
                publishHealth(profileId, ProxyHealthStatus.AVAILABLE, measured.latencyMs)

                val elapsed = SystemClock.elapsedRealtime()
                if (elapsed - lastSecondaryScanElapsed < failoverPolicy.tuning.backupScanIntervalMs) {
                    continue
                }
                lastSecondaryScanElapsed = elapsed

                if (maybeSchedulePrimaryRestore(generation, current)) return@Thread
                backupCursor = scanOneBackup(current, backupCursor)
            }
        }, "APL-auto-health")

        synchronized(lock) {
            if (generation != sessionGeneration || stopping) return
            monitorWorker = thread
        }
        thread.start()
    }

    private fun isSessionActive(generation: Long): Boolean = synchronized(lock) {
        generation == sessionGeneration && !stopping && worker?.isAlive == true
    }

    private fun maybeSchedulePrimaryRestore(
        generation: Long,
        current: PreparedProxy,
    ): Boolean {
        if (store.getRestorePolicy() != PrimaryRestorePolicy.RETURN_TO_PRIMARY) return false
        val primaryId = store.getPrimaryProfileId() ?: return false
        if (primaryId == current.resolved.profile.id) return false
        val primary = runCatching { store.loadProfile(primaryId) }.getOrNull() ?: return false

        publishHealth(primaryId, ProxyHealthStatus.CHECKING, null)
        val measured = runCatching { probe.resolveMeasured(primary.profile, primary.password) }.getOrNull()
        if (measured == null) {
            publishHealth(primaryId, ProxyHealthStatus.UNAVAILABLE, null)
            return false
        }

        publishHealth(primaryId, ProxyHealthStatus.AVAILABLE, measured.latencyMs)
        val now = System.currentTimeMillis()
        if (!failoverPolicy.shouldRestorePrimary(
                policy = store.getRestorePolicy(),
                currentProfileId = current.resolved.profile.id,
                primaryProfileId = primaryId,
                primaryAvailable = true,
                nowMs = now,
                lastSwitchAtMs = store.getLastFailoverAtMs(),
            )
        ) return false

        mainHandler.post {
            requestAutoHandoff(generation, current, restorationProfile = primary.profile)
        }
        return true
    }

    private fun scanOneBackup(current: PreparedProxy, cursor: Int): Int {
        val primaryId = store.getPrimaryProfileId()
        val candidates = store.listProfiles().filter {
            it.id != current.resolved.profile.id &&
                !(store.getRestorePolicy() == PrimaryRestorePolicy.RETURN_TO_PRIMARY && it.id == primaryId)
        }
        if (candidates.isEmpty()) return 0
        val index = cursor % candidates.size
        val profile = candidates[index]
        val resolved = runCatching { store.loadProfile(profile.id) }.getOrNull()
            ?: return (index + 1) % candidates.size

        publishHealth(profile.id, ProxyHealthStatus.CHECKING, null)
        val measured = runCatching { probe.resolveMeasured(resolved.profile, resolved.password) }.getOrNull()
        if (measured == null) publishHealth(profile.id, ProxyHealthStatus.UNAVAILABLE, null)
        else publishHealth(profile.id, ProxyHealthStatus.AVAILABLE, measured.latencyMs)
        return (index + 1) % candidates.size
    }

    private fun registerNetworkCallback() {
        if (networkCallback != null) return
        val manager = getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = noteNetworkTransition()
            override fun onLost(network: Network) = noteNetworkTransition()
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                noteNetworkTransition()
            }
        }
        if (runCatching { manager.registerDefaultNetworkCallback(callback) }.isSuccess) {
            networkCallback = callback
        }
    }

    private fun noteNetworkTransition() {
        lastNetworkTransitionElapsedMs = SystemClock.elapsedRealtime()
    }

    private fun stopAutoMonitor() {
        val thread = synchronized(lock) {
            val current = monitorWorker
            monitorWorker = null
            current
        }
        if (thread != null && thread !== Thread.currentThread()) thread.interrupt()
        val callback = networkCallback
        networkCallback = null
        if (callback != null) {
            runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(callback) }
        }
    }

    private fun requestAutoHandoff(
        generation: Long,
        current: PreparedProxy,
        restorationProfile: ProxyProfile?,
    ) {
        val proceed = synchronized(lock) {
            if (generation != sessionGeneration || stopping || failoverHandoff) {
                false
            } else {
                failoverHandoff = true
                stopping = true
                sessionGeneration += 1
                preflightWorker = null
                activePrepared = null
                true
            }
        }
        if (!proceed) return

        val now = System.currentTimeMillis()
        if (restorationProfile == null) {
            val profile = current.resolved.profile
            publishHealth(profile.id, ProxyHealthStatus.UNAVAILABLE, null)
            store.markRecentlyFailedProfile(profile.id, now)
            publishPoolEvent("proxy unavailable", profile.id, profile.name, "confirmed health failure")
        } else {
            store.clearRecentlyFailedProfile()
            publishPoolEvent("restored", restorationProfile.id, restorationProfile.name, "primary recovered")
        }
        store.setLastFailoverAtMs(now)
        publishState(
            STATE_CONNECTING,
            if (restorationProfile == null) "Авто: переключаемся на резервный прокси…"
            else "Авто: возвращаем основной прокси…",
        )

        stopAutoMonitor()
        runCatching { engine.stop() }
        synchronized(lock) {
            tunFd?.runCatching { close() }
            tunFd = null
            worker = null
        }

        // Do not call stopSelf(): START_STICKY keeps this VpnService in the
        // started state. Android recreates a killed sticky foreground service
        // even when a fresh background start would otherwise be restricted.
        // The new :vpn process re-runs preflight and selects the next Auto candidate.
        mainHandler.postDelayed({ Process.killProcess(Process.myPid()) }, PROCESS_HANDOFF_KILL_DELAY_MS)
    }

    private fun publishHealth(
        profileId: String,
        status: ProxyHealthStatus,
        latencyMs: Long?,
    ) {
        val intent = Intent(this, PoolStateRelayReceiver::class.java)
            .setAction(ACTION_POOL_HEALTH)
            .putExtra(EXTRA_PROFILE_ID, profileId)
            .putExtra(EXTRA_HEALTH_STATUS, status.name)
            .putExtra(EXTRA_TIMESTAMP_MS, System.currentTimeMillis())
        if (latencyMs != null) intent.putExtra(EXTRA_LATENCY_MS, latencyMs)
        sendBroadcast(intent)
    }

    private fun publishPoolEvent(
        type: String,
        profileId: String?,
        profileName: String?,
        detail: String?,
    ) {
        val intent = Intent(this, PoolStateRelayReceiver::class.java)
            .setAction(ACTION_POOL_EVENT)
            .putExtra(EXTRA_EVENT_TYPE, type)
            .putExtra(EXTRA_TIMESTAMP_MS, System.currentTimeMillis())
        if (profileId != null) intent.putExtra(EXTRA_PROFILE_ID, profileId)
        if (profileName != null) intent.putExtra(EXTRA_PROFILE_NAME, profileName)
        if (detail != null) intent.putExtra(EXTRA_EVENT_DETAIL, detail)
        sendBroadcast(intent)
    }

    private fun failStartFromWorker(generation: Long, message: String) {
        mainHandler.post {
            failStartForSession(generation, message)
        }
    }

    private fun failStartForSession(generation: Long, message: String) {
        val active = synchronized(lock) {
            if (generation != sessionGeneration || stopping) {
                false
            } else {
                preflightWorker = null
                true
            }
        }
        if (!active) return
        failStart(message)
    }

    private fun onEngineExit(generation: Long, result: Int) {
        var reportExit = false
        var autoPrepared: PreparedProxy? = null
        synchronized(lock) {
            if (generation == sessionGeneration && worker === Thread.currentThread()) {
                worker = null
                tunFd?.runCatching { close() }
                tunFd = null
                reportExit = !stopping
                autoPrepared = activePrepared?.takeIf { it.autoSelection }
            }
        }
        if (!reportExit) return

        val failedAuto = autoPrepared
        if (failedAuto != null) {
            mainHandler.post {
                requestAutoHandoff(generation, failedAuto, restorationProfile = null)
            }
            return
        }

        if (result == 0) {
            publishState(STATE_DISCONNECTED, "Отключено")
        } else {
            publishState(STATE_ERROR, "Proxy engine остановился (код $result)")
        }
        stopForegroundCompat()
        stopSelf()
        terminateVpnProcess()
    }

    private fun stopTunnel() {
        stopAutoMonitor()
        val probeThread = synchronized(lock) {
            stopping = true
            sessionGeneration += 1
            val currentProbe = preflightWorker
            preflightWorker = null
            activePrepared = null
            currentProbe
        }
        probeThread?.interrupt()

        publishState(STATE_DISCONNECTING, "Отключение…")
        runCatching { engine.stop() }
        synchronized(lock) {
            tunFd?.runCatching { close() }
            tunFd = null
            worker = null
        }
        publishState(STATE_DISCONNECTED, "Отключено")
        stopForegroundCompat()
        stopSelf()
        terminateVpnProcess()
    }

    private fun shutdownEngineSilently() {
        stopAutoMonitor()
        val probeThread = synchronized(lock) {
            stopping = true
            sessionGeneration += 1
            val currentProbe = preflightWorker
            preflightWorker = null
            currentProbe
        }
        probeThread?.interrupt()

        runCatching { engine.stop() }
        synchronized(lock) {
            tunFd?.runCatching { close() }
            tunFd = null
            worker = null
        }
    }

    private fun failStart(message: String) {
        publishState(STATE_ERROR, message)
        stopForegroundCompat()
        stopSelf()
        // The VPN process owns its own SharedPreferences instance. Kill it after
        // a failed preflight so the next connect starts fresh and reads any
        // active-profile change committed by the UI process.
        terminateVpnProcess()
    }

    private fun terminateVpnProcess() {
        mainHandler.post {
            Process.killProcess(Process.myPid())
        }
    }

    private fun publishState(state: String, detail: String?) {
        store.setLastState(state, detail)
        sendBroadcast(
            Intent(ACTION_STATE)
                .setPackage(packageName)
                .putExtra(EXTRA_STATE, state)
                .putExtra(EXTRA_DETAIL, detail),
        )
    }

    private fun protocolLabel(type: ProxyType): String = when (type) {
        ProxyType.AUTO -> "Авто"
        ProxyType.HTTPS -> "HTTPS-proxy (TLS)"
        ProxyType.HTTP -> "HTTP/HTTPS (CONNECT)"
        ProxyType.SOCKS5 -> "SOCKS5"
    }

    private fun ensureNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Proxy Launcher VPN", NotificationManager.IMPORTANCE_LOW),
        )
    }

    private fun notification(text: String): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle("Arvectum Proxy Launcher")
            .setContentText(text)
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
    }

    private fun startForegroundCompat(text: String) {
        val notification = notification(text)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= 24) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private data class PreparedProxy(
        val resolved: ResolvedProxyProfile,
        val selectedProfile: ProxyProfile,
        val autoSelection: Boolean,
        val latencyMs: Long,
    )

    companion object {
        const val ACTION_CONNECT = "ru.arvectum.proxylauncher.CONNECT"
        const val ACTION_DISCONNECT = "ru.arvectum.proxylauncher.DISCONNECT"
        const val ACTION_STATE = "ru.arvectum.proxylauncher.STATE"
        const val ACTION_POOL_UPDATE = "ru.arvectum.proxylauncher.POOL_UPDATE"
        const val ACTION_POOL_HEALTH = "ru.arvectum.proxylauncher.POOL_HEALTH"
        const val ACTION_POOL_EVENT = "ru.arvectum.proxylauncher.POOL_EVENT"
        const val EXTRA_STATE = "state"
        const val EXTRA_DETAIL = "detail"
        const val EXTRA_PROFILE_ID = "profile_id"
        const val EXTRA_PROFILE_NAME = "profile_name"
        const val EXTRA_HEALTH_STATUS = "health_status"
        const val EXTRA_LATENCY_MS = "latency_ms"
        const val EXTRA_EVENT_TYPE = "event_type"
        const val EXTRA_EVENT_DETAIL = "event_detail"
        const val EXTRA_TIMESTAMP_MS = "timestamp_ms"

        const val STATE_DISCONNECTED = "DISCONNECTED"
        const val STATE_CONNECTING = "CONNECTING"
        const val STATE_CONNECTED = "CONNECTED"
        const val STATE_DISCONNECTING = "DISCONNECTING"
        const val STATE_ERROR = "ERROR"

        private const val CHANNEL_ID = "proxy_vpn"
        private const val NOTIFICATION_ID = 1001
        private const val CONNECT_CONFIRM_DELAY_MS = 500L
        private const val PROCESS_HANDOFF_KILL_DELAY_MS = 300L
        private const val SWITCH_EVENT_WINDOW_MS = 30_000L
        private const val MAX_AUTO_ERROR_LENGTH = 520
        private const val ENGINE_START_FAILURE = -1000
    }
}
