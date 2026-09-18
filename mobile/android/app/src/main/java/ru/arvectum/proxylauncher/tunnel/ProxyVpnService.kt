package ru.arvectum.proxylauncher.tunnel

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import ru.arvectum.proxylauncher.MainActivity
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
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var store: SecureProfileStore
    private var tunFd: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var preflightWorker: Thread? = null
    private var sessionGeneration: Long = 0
    @Volatile private var stopping = false

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
        if (!stopping) shutdownEngineSilently()
        super.onDestroy()
    }

    private fun startTunnel() {
        val generation = synchronized(lock) {
            if (worker?.isAlive == true || preflightWorker?.isAlive == true || tunFd != null) return
            stopping = false
            sessionGeneration += 1
            sessionGeneration
        }

        startForegroundCompat("Проверяем прокси…")
        publishState(STATE_CONNECTING, "Проверяем прокси…")

        val thread = Thread({
            val resolved = try {
                store.loadActive() ?: run {
                    failStartFromWorker(generation, "Сначала добавьте прокси")
                    return@Thread
                }
            } catch (_: Exception) {
                failStartFromWorker(generation, "Не удалось прочитать сохранённые credentials")
                return@Thread
            }

            val selectedProfile = try {
                probe.resolve(resolved.profile, resolved.password) { candidate ->
                    mainHandler.post {
                        publishPreflightProgress(generation, candidate)
                    }
                }
            } catch (e: ProxyProbeException) {
                failStartFromWorker(generation, e.message ?: "Прокси недоступен")
                return@Thread
            } catch (e: IllegalStateException) {
                failStartFromWorker(generation, e.message ?: "Внутренняя ошибка проверки прокси")
                return@Thread
            } catch (_: Exception) {
                failStartFromWorker(generation, "Не удалось проверить прокси")
                return@Thread
            }

            mainHandler.post {
                continueStartAfterPreflight(generation, resolved, selectedProfile)
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
        resolved: ResolvedProxyProfile,
        selectedProfile: ProxyProfile,
    ) {
        synchronized(lock) {
            if (generation != sessionGeneration || stopping) return
            preflightWorker = null
        }

        publishState(
            STATE_CONNECTING,
            "Прокси проверен: ${protocolLabel(selectedProfile.type)}. Создаём VPN…",
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
                val label = protocolLabel(selectedProfile.type)
                startForegroundCompat("Подключено · $label")
                publishState(
                    STATE_CONNECTED,
                    "Подключено · $label · ${resolved.profile.host}:${resolved.profile.port}",
                )
            }
        }, CONNECT_CONFIRM_DELAY_MS)
    }

    private fun publishPreflightProgress(generation: Long, type: ProxyType) {
        val active = synchronized(lock) {
            generation == sessionGeneration && !stopping
        }
        if (!active) return
        publishState(STATE_CONNECTING, "Проверяем: ${protocolLabel(type)}…")
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
        synchronized(lock) {
            if (generation == sessionGeneration && worker === Thread.currentThread()) {
                worker = null
                tunFd?.runCatching { close() }
                tunFd = null
                reportExit = !stopping
            }
        }
        if (!reportExit) return

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
        val probeThread = synchronized(lock) {
            stopping = true
            sessionGeneration += 1
            val currentProbe = preflightWorker
            preflightWorker = null
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

    companion object {
        const val ACTION_CONNECT = "ru.arvectum.proxylauncher.CONNECT"
        const val ACTION_DISCONNECT = "ru.arvectum.proxylauncher.DISCONNECT"
        const val ACTION_STATE = "ru.arvectum.proxylauncher.STATE"
        const val EXTRA_STATE = "state"
        const val EXTRA_DETAIL = "detail"

        const val STATE_DISCONNECTED = "DISCONNECTED"
        const val STATE_CONNECTING = "CONNECTING"
        const val STATE_CONNECTED = "CONNECTED"
        const val STATE_DISCONNECTING = "DISCONNECTING"
        const val STATE_ERROR = "ERROR"

        private const val CHANNEL_ID = "proxy_vpn"
        private const val NOTIFICATION_ID = 1001
        private const val CONNECT_CONFIRM_DELAY_MS = 500L
        private const val ENGINE_START_FAILURE = -1000
    }
}
