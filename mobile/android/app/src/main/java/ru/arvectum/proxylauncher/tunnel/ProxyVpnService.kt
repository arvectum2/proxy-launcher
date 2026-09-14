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
import ru.arvectum.proxylauncher.MainActivity
import ru.arvectum.proxylauncher.storage.SecureProfileStore

class ProxyVpnService : VpnService() {
    private val lock = Any()
    private val engine: ProxyEngineAdapter = Tun2ProxyEngineAdapter()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var store: SecureProfileStore
    private var tunFd: ParcelFileDescriptor? = null
    private var worker: Thread? = null
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
        super.onRevoke()
    }

    override fun onDestroy() {
        shutdownEngineSilently()
        super.onDestroy()
    }

    private fun startTunnel() {
        synchronized(lock) {
            if (worker?.isAlive == true || tunFd != null) return
            stopping = false
        }

        startForegroundCompat("Подключение…")
        publishState(STATE_CONNECTING, "Подключение…")

        val resolved = try {
            store.loadActive() ?: run {
                failStart("Сначала добавьте прокси")
                return
            }
        } catch (_: Exception) {
            failStart("Не удалось прочитать сохранённые credentials")
            return
        }

        val tun = try {
            val builder = Builder()
                .setSession("Arvectum Proxy Launcher")
                .setMtu(Tun2ProxyEngineAdapter.TUN_MTU)
                .addAddress("10.111.0.1", 32)
                .addRoute("0.0.0.0", 0)
                .addAddress("fd00:111::1", 128)
                .addRoute("::", 0)
                .addDnsServer("198.18.0.1")

            // Native proxy sockets must stay outside our own VPN or they would loop back into TUN.
            builder.addDisallowedApplication(packageName)
            builder.establish() ?: error("VpnService.Builder.establish() returned null")
        } catch (_: Exception) {
            failStart("Android не смог создать VPN-интерфейс")
            return
        }

        synchronized(lock) { tunFd = tun }
        val thread = Thread({
            val result = try {
                engine.run(tun, resolved.profile, resolved.password)
            } catch (_: Throwable) {
                ENGINE_START_FAILURE
            }
            onEngineExit(result)
        }, "APL-tun2proxy")
        synchronized(lock) { worker = thread }
        thread.start()

        mainHandler.postDelayed({
            val running = synchronized(lock) {
                worker === thread && thread.isAlive && !stopping
            }
            if (running) {
                startForegroundCompat("Подключено: ${resolved.profile.name}")
                publishState(STATE_CONNECTED, "Подключено: ${resolved.profile.name}")
            }
        }, CONNECT_CONFIRM_DELAY_MS)
    }

    private fun onEngineExit(result: Int) {
        var reportExit = false
        synchronized(lock) {
            if (worker === Thread.currentThread()) {
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
            publishState(STATE_ERROR, "Proxy engine остановился")
        }
        stopForegroundCompat()
        stopSelf()
    }

    private fun stopTunnel() {
        synchronized(lock) { stopping = true }
        runCatching { engine.stop() }
        synchronized(lock) {
            tunFd?.runCatching { close() }
            tunFd = null
            worker = null
        }
        publishState(STATE_DISCONNECTED, "Отключено")
        stopForegroundCompat()
        stopSelf()
    }

    private fun shutdownEngineSilently() {
        synchronized(lock) { stopping = true }
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

    private fun publishState(state: String, detail: String?) {
        store.setLastState(state, detail)
        sendBroadcast(
            Intent(ACTION_STATE)
                .setPackage(packageName)
                .putExtra(EXTRA_STATE, state)
                .putExtra(EXTRA_DETAIL, detail),
        )
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
        const val STATE_ERROR = "ERROR"

        private const val CHANNEL_ID = "proxy_vpn"
        private const val NOTIFICATION_ID = 1001
        private const val CONNECT_CONFIRM_DELAY_MS = 350L
        private const val ENGINE_START_FAILURE = -1000
    }
}
