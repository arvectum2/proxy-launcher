package ru.arvectum.proxylauncher.tunnel

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.SystemClock
import java.net.InetAddress
import ru.arvectum.proxylauncher.MainActivity
import ru.arvectum.proxylauncher.gateway.FreeGatewayClient
import ru.arvectum.proxylauncher.gateway.FreeSessionRefreshPolicy
import ru.arvectum.proxylauncher.model.PrimaryRestorePolicy
import ru.arvectum.proxylauncher.model.ProxyHealthStatus
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType
import ru.arvectum.proxylauncher.routing.SiteExclusionPolicy
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
    private lateinit var engine: ProxyEngineAdapter
    private val probe = ProxyProtocolProbe()
    private val failoverPolicy = FailoverPolicy()
    private val freeGatewayClient = FreeGatewayClient()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var store: SecureProfileStore
    private var tunFd: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var preflightWorker: Thread? = null
    private var monitorWorker: Thread? = null
    private var freeSessionRefreshWorker: Thread? = null
    private var freeRecoveryResetRunnable: Runnable? = null
    private var activePrepared: PreparedProxy? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val physicalNetworks = linkedSetOf<Network>()
    private var sessionGeneration: Long = 0
    @Volatile private var stopping = false
    @Volatile private var failoverHandoff = false
    @Volatile private var lastNetworkTransitionElapsedMs = 0L
    @Volatile private var networkTransitionSerial = 0L
    @Volatile private var underlyingNetwork: Network? = null

    override fun onCreate() {
        super.onCreate()
        store = SecureProfileStore(this)
        engine = Tun2ProxyEngineAdapter()
        ensureNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT -> {
                store.clearVpnProcessRestartPending()
                stopTunnel()
                return START_NOT_STICKY
            }
            ACTION_RECONCILE -> reconcileTunnelAfterForegroundResume()
            ACTION_CONNECT -> {
                store.clearVpnProcessRestartPending()
                startTunnel()
            }
            null -> {
                if (store.consumeVpnProcessRestartPending()) {
                    startTunnel()
                } else {
                    stopForegroundCompat()
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
            else -> return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onRevoke() {
        store.clearVpnProcessRestartPending()
        stopTunnel()
    }

    override fun onDestroy() {
        cancelFreeRecoveryReset()
        stopFreeSessionRefresh()
        stopAutoMonitor()
        if (!stopping) shutdownEngineSilently()
        super.onDestroy()
    }

    private fun reconcileTunnelAfterForegroundResume() {
        val snapshot = synchronized(lock) {
            ReconcileSnapshot(
                stopping = stopping,
                failoverHandoff = failoverHandoff,
                workerAlive = worker?.isAlive == true,
                preflightAlive = preflightWorker?.isAlive == true,
                tunPresent = tunFd != null,
                prepared = activePrepared,
            )
        }
        val action = TunnelServiceReconcilePolicy.decide(
            stopping = snapshot.stopping,
            failoverHandoff = snapshot.failoverHandoff,
            workerAlive = snapshot.workerAlive,
            preflightAlive = snapshot.preflightAlive,
            tunPresent = snapshot.tunPresent,
            hasActivePrepared = snapshot.prepared != null,
        )
        when (action) {
            TunnelServiceReconcileAction.START_TUNNEL -> startTunnel()
            TunnelServiceReconcileAction.REPORT_CONNECTED -> {
                snapshot.prepared?.let(::publishConnectedState) ?: startTunnel()
            }
            TunnelServiceReconcileAction.REPORT_CONNECTING -> {
                val detail = if (snapshot.stopping || snapshot.failoverHandoff) {
                    "Переподключаем VPN…"
                } else {
                    "Подключение продолжается…"
                }
                publishState(STATE_CONNECTING, detail)
            }
        }
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
            val proxyPrepared = try {
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

            val prepared = try {
                proxyPrepared.copy(siteExclusions = resolveSiteExclusions())
            } catch (e: Exception) {
                failStartFromWorker(
                    generation,
                    e.message ?: "Не удалось применить исключения сайтов",
                )
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

    private fun resolveSiteExclusions(): SiteExclusionPlan {
        val entries = store.getSiteExclusions()
        if (entries.isEmpty()) return SiteExclusionPlan.EMPTY

        val connectivity = getSystemService(ConnectivityManager::class.java)
        val network = connectivity.activeNetwork
            ?: throw IllegalStateException("Нет активной сети для применения исключений")
        val capabilities = connectivity.getNetworkCapabilities(network)
        if (capabilities == null ||
            !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
            !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        ) {
            throw IllegalStateException("Не удалось определить физическую сеть для исключений")
        }

        val dnsServers = connectivity.getLinkProperties(network)
            ?.dnsServers
            .orEmpty()
            .distinctBy { it.hostAddress }
        if (dnsServers.isEmpty()) {
            throw IllegalStateException("Не удалось определить системный DNS для исключений")
        }

        val resolved = linkedMapOf<String, InetAddress>()
        entries.forEach { entry ->
            val addresses = runCatching { network.getAllByName(entry).toList() }
                .getOrElse { throw IllegalStateException("Не удалось разрешить исключение: $entry") }
            if (addresses.isEmpty()) {
                throw IllegalStateException("Исключение не имеет IP-адресов: $entry")
            }
            addresses.forEach { address -> resolved[address.hostAddress] = address }
        }
        if (resolved.size > SiteExclusionPolicy.MAX_RESOLVED_ADDRESSES) {
            throw IllegalStateException("Слишком много IP-адресов в исключениях")
        }

        val bypass = (resolved.values + dnsServers)
            .distinctBy { it.hostAddress }
        return SiteExclusionPlan(
            enabled = true,
            bypassAddresses = bypass,
            dnsServers = dnsServers,
            dnsMode = TunnelDnsMode.DIRECT,
        )
    }

    private fun applySiteExclusionRoutes(builder: Builder, plan: SiteExclusionPlan) {
        if (!plan.enabled) {
            builder.addRoute("0.0.0.0", 0)
            builder.addRoute("::", 0)
            return
        }

        if (Build.VERSION.SDK_INT >= 33) {
            builder.addRoute("0.0.0.0", 0)
            builder.addRoute("::", 0)
            plan.bypassAddresses.forEach { address ->
                val prefix = if (address.address.size == 4) 32 else 128
                builder.excludeRoute(IpPrefix(address, prefix))
            }
            return
        }

        SiteExclusionPolicy.complementRoutes(plan.bypassAddresses, 4).forEach { route ->
            builder.addRoute(route.address, route.prefixLength)
        }
        SiteExclusionPolicy.complementRoutes(plan.bypassAddresses, 16).forEach { route ->
            builder.addRoute(route.address, route.prefixLength)
        }
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
                .addAddress("fd00:111::1", 128)

            applySiteExclusionRoutes(builder, prepared.siteExclusions)
            if (prepared.siteExclusions.enabled) {
                prepared.siteExclusions.dnsServers.forEach { builder.addDnsServer(it) }
            } else {
                builder.addDnsServer("198.18.0.1")
            }
            builder.addDisallowedApplication(packageName)
            store.getAppExclusions().forEach { excludedPackage ->
                runCatching { builder.addDisallowedApplication(excludedPackage) }
            }
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
                engine.run(
                    tun,
                    selectedProfile,
                    resolved.password,
                    prepared.siteExclusions.dnsMode,
                )
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
                completeConnectedSession(generation, prepared)
            }
        }, CONNECT_CONFIRM_DELAY_MS)
    }

    private fun completeConnectedSession(generation: Long, prepared: PreparedProxy) {
        val active = synchronized(lock) {
            generation == sessionGeneration &&
                !stopping &&
                worker?.isAlive == true &&
                activePrepared === prepared
        }
        if (!active) return

        publishConnectedState(prepared)
        if (prepared.autoSelection) {
            startAutoMonitor(generation, prepared)
        } else {
            registerNetworkCallback()
        }
        prepared.freeSessionExpiresAtEpochSeconds?.let { expiresAt ->
            startFreeSessionRefresh(generation, expiresAt)
            scheduleFreeRecoveryReset(generation)
        }
    }

    private fun publishConnectedState(prepared: PreparedProxy) {
        val resolved = prepared.resolved
        val selectedProfile = prepared.selectedProfile
        val selectionLabel = if (prepared.autoSelection) {
            "Авто → ${resolved.profile.name}"
        } else {
            resolved.profile.name
        }
        val label = protocolLabel(selectedProfile.type)
        startForegroundCompat("Подключено · $selectionLabel")
        publishState(
            STATE_CONNECTED,
            "Подключено · $selectionLabel · $label · ${resolved.profile.host}:${resolved.profile.port}",
        )
    }

    private fun resolveProxySelection(generation: Long): PreparedProxy {
        val freeLocationId = store.getActiveFreeLocationId()
        if (freeLocationId != null) {
            val label = store.getActiveFreeLocationLabel()?.ifBlank { null } ?: freeLocationId
            val displayName = "$label · бесплатно"
            val session = try {
                freeGatewayClient.createSession(freeLocationId, displayName)
            } catch (e: Exception) {
                throw ProxyProbeException(
                    "Не удалось получить бесплатный прокси: ${e.message ?: "gateway недоступен"}",
                )
            }
            val resolved = ResolvedProxyProfile(session.profile, session.password)
            publishHealth(resolved.profile.id, ProxyHealthStatus.CHECKING, null)
            val measured = try {
                probe.resolveMeasured(resolved.profile, resolved.password) { candidate ->
                    mainHandler.post {
                        publishPreflightProgress(
                            generation = generation,
                            profileName = displayName,
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
            return PreparedProxy(
                resolved = resolved,
                selectedProfile = measured.profile,
                autoSelection = false,
                latencyMs = measured.latencyMs,
                freeSessionExpiresAtEpochSeconds = session.expiresAtEpochSeconds,
            )
        }

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
            var observedNetworkTransitionSerial = networkTransitionSerial

            while (isSessionActive(generation)) {
                try {
                    Thread.sleep(failoverPolicy.tuning.healthIntervalMs)
                } catch (_: InterruptedException) {
                    return@Thread
                }
                if (!isSessionActive(generation)) return@Thread

                val transitionSerial = networkTransitionSerial
                if (transitionSerial != observedNetworkTransitionSerial) {
                    observedNetworkTransitionSerial = transitionSerial
                    consecutiveFailures = 0
                }

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

        selectPhysicalNetwork(manager)?.let { initial ->
            synchronized(lock) { physicalNetworks += initial }
            underlyingNetwork = initial
            runCatching { setUnderlyingNetworks(arrayOf(initial)) }
        }

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                synchronized(lock) { physicalNetworks += network }
                schedulePhysicalNetworkReconcile()
            }

            override fun onLost(network: Network) {
                synchronized(lock) { physicalNetworks -= network }
                schedulePhysicalNetworkReconcile()
            }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                synchronized(lock) {
                    if (isPhysicalInternetCapabilities(capabilities)) {
                        physicalNetworks += network
                    } else {
                        physicalNetworks -= network
                    }
                }
                schedulePhysicalNetworkReconcile()
            }
        }
        if (runCatching { manager.registerNetworkCallback(request, callback) }.isSuccess) {
            networkCallback = callback
        }
    }

    private fun schedulePhysicalNetworkReconcile() {
        mainHandler.removeCallbacks(networkReconcileRunnable)
        mainHandler.postDelayed(networkReconcileRunnable, NETWORK_RECONCILE_DELAY_MS)
    }

    private val networkReconcileRunnable = Runnable {
        reconcilePhysicalNetwork()
    }

    private fun reconcilePhysicalNetwork() {
        if (stopping || failoverHandoff) return
        val manager = getSystemService(ConnectivityManager::class.java)
        val next = selectPhysicalNetwork(manager) ?: return
        val previous = underlyingNetwork

        if (previous == null) {
            underlyingNetwork = next
            runCatching { setUnderlyingNetworks(arrayOf(next)) }
            return
        }

        if (previous == next) {
            runCatching { setUnderlyingNetworks(arrayOf(next)) }
            return
        }

        underlyingNetwork = next
        runCatching { setUnderlyingNetworks(arrayOf(next)) }
        noteNetworkTransition()

        val generation = synchronized(lock) {
            if (stopping || failoverHandoff || worker?.isAlive != true) null
            else sessionGeneration
        } ?: return
        requestNetworkHandoff(generation)
    }

    private fun selectPhysicalNetwork(manager: ConnectivityManager): Network? {
        val active = manager.activeNetwork
        if (active != null && isPhysicalInternetNetwork(manager, active)) return active

        val candidates = synchronized(lock) { physicalNetworks.toList() }
            .filter { isPhysicalInternetNetwork(manager, it) }
        if (candidates.isEmpty()) return null

        val current = underlyingNetwork
        if (current != null && current in candidates && isValidatedNetwork(manager, current)) {
            return current
        }
        return candidates.firstOrNull { isValidatedNetwork(manager, it) }
            ?: current?.takeIf { it in candidates }
            ?: candidates.first()
    }

    private fun isPhysicalInternetNetwork(
        manager: ConnectivityManager,
        network: Network,
    ): Boolean {
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        return isPhysicalInternetCapabilities(capabilities)
    }

    private fun isPhysicalInternetCapabilities(capabilities: NetworkCapabilities): Boolean =
        capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)

    private fun isValidatedNetwork(manager: ConnectivityManager, network: Network): Boolean =
        manager.getNetworkCapabilities(network)
            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true

    private fun noteNetworkTransition() {
        lastNetworkTransitionElapsedMs = SystemClock.elapsedRealtime()
        networkTransitionSerial += 1
    }

    private fun stopAutoMonitor() {
        val thread = synchronized(lock) {
            val current = monitorWorker
            monitorWorker = null
            current
        }
        if (thread != null && thread !== Thread.currentThread()) thread.interrupt()
        mainHandler.removeCallbacks(networkReconcileRunnable)
        val callback = networkCallback
        networkCallback = null
        synchronized(lock) { physicalNetworks.clear() }
        underlyingNetwork = null
        runCatching { setUnderlyingNetworks(null) }
        if (callback != null) {
            runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(callback) }
        }
    }

    private fun scheduleFreeRecoveryReset(generation: Long) {
        cancelFreeRecoveryReset()
        val runnable = Runnable {
            val stable = synchronized(lock) {
                generation == sessionGeneration &&
                    !stopping &&
                    activePrepared?.freeSessionExpiresAtEpochSeconds != null &&
                    worker?.isAlive == true
            }
            if (stable) {
                runCatching { store.clearFreeRecoveryState() }
            }
        }
        freeRecoveryResetRunnable = runnable
        mainHandler.postDelayed(runnable, FreeTunnelRecoveryPolicy.STABLE_RESET_MS)
    }

    private fun cancelFreeRecoveryReset() {
        freeRecoveryResetRunnable?.let(mainHandler::removeCallbacks)
        freeRecoveryResetRunnable = null
    }

    private fun startFreeSessionRefresh(generation: Long, expiresAtEpochSeconds: Long) {
        stopFreeSessionRefresh()
        val delayMs = FreeSessionRefreshPolicy.delayMillis(
            nowEpochSeconds = System.currentTimeMillis() / 1_000L,
            expiresAtEpochSeconds = expiresAtEpochSeconds,
        )
        val thread = Thread({
            try {
                Thread.sleep(delayMs)
            } catch (_: InterruptedException) {
                return@Thread
            }
            mainHandler.post { requestFreeSessionRefresh(generation) }
        }, "APL-free-session-refresh")
        synchronized(lock) {
            if (generation != sessionGeneration || stopping) return
            freeSessionRefreshWorker = thread
        }
        thread.start()
    }

    private fun stopFreeSessionRefresh() {
        val thread = synchronized(lock) {
            val current = freeSessionRefreshWorker
            freeSessionRefreshWorker = null
            current
        }
        if (thread != null && thread !== Thread.currentThread()) thread.interrupt()
    }

    private fun requestFreeSessionRefresh(generation: Long) {
        val proceed = synchronized(lock) {
            if (generation != sessionGeneration || stopping || failoverHandoff || worker?.isAlive != true) {
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

        startForegroundCompat("Обновляем бесплатную прокси-сессию…")
        publishState(STATE_CONNECTING, "Обновляем бесплатную прокси-сессию…")
        cancelFreeRecoveryReset()
        stopFreeSessionRefresh()
        stopAutoMonitor()
        runCatching { engine.stop() }
        synchronized(lock) {
            tunFd?.runCatching { close() }
            tunFd = null
            worker = null
        }
        store.markVpnProcessRestartPending()
        mainHandler.postDelayed({ Process.killProcess(Process.myPid()) }, PROCESS_HANDOFF_KILL_DELAY_MS)
    }

    private fun requestNetworkHandoff(generation: Long) {
        val proceed = synchronized(lock) {
            if (generation != sessionGeneration || stopping || failoverHandoff || worker?.isAlive != true) {
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

        publishPoolEvent("network changed", null, null, "physical network changed")
        startForegroundCompat("Сеть изменилась · переподключаем VPN…")
        publishState(STATE_CONNECTING, "Сеть изменилась · переподключаем VPN…")

        cancelFreeRecoveryReset()
        stopFreeSessionRefresh()
        stopAutoMonitor()
        runCatching { engine.stop() }
        synchronized(lock) {
            tunFd?.runCatching { close() }
            tunFd = null
            worker = null
        }

        // tun2proxy keeps long-lived upstream sockets that cannot migrate to a
        // replacement Wi-Fi/cellular network. Recreate only the isolated :vpn
        // process so fresh sockets are opened on the new physical carrier while
        // preserving Android's existing VPN permission grant.
        store.markVpnProcessRestartPending()
        mainHandler.postDelayed({ Process.killProcess(Process.myPid()) }, PROCESS_HANDOFF_KILL_DELAY_MS)
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

        cancelFreeRecoveryReset()
        stopFreeSessionRefresh()
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
        store.markVpnProcessRestartPending()
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
        var freePrepared: PreparedProxy? = null
        synchronized(lock) {
            if (generation == sessionGeneration && worker === Thread.currentThread()) {
                worker = null
                tunFd?.runCatching { close() }
                tunFd = null
                reportExit = !stopping
                autoPrepared = activePrepared?.takeIf { it.autoSelection }
                freePrepared = activePrepared?.takeIf {
                    it.freeSessionExpiresAtEpochSeconds != null
                }
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

        if (freePrepared != null) {
            mainHandler.post { requestFreeEngineRecovery(generation, result) }
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

    private fun requestFreeEngineRecovery(generation: Long, result: Int) {
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
        val decision = FreeTunnelRecoveryPolicy.decide(
            nowMs = now,
            windowStartedAtMs = store.getFreeRecoveryWindowStartedAtMs(),
            attemptCount = store.getFreeRecoveryAttemptCount(),
        )
        if (!decision.shouldRetry) {
            runCatching { store.clearFreeRecoveryState() }
            publishState(
                STATE_ERROR,
                "Бесплатный прокси нестабилен. Повторите подключение через несколько секунд.",
            )
            stopForegroundCompat()
            stopSelf()
            terminateVpnProcess()
            return
        }

        runCatching {
            store.setFreeRecoveryState(
                decision.windowStartedAtMs,
                decision.attemptCount,
            )
        }
        publishPoolEvent(
            "free reconnect",
            store.getActiveFreeLocationId()?.let { "free:$it" },
            store.getActiveFreeLocationLabel(),
            "engine exit " + result + " · retry " + decision.attemptCount,
        )
        startForegroundCompat("Связь прервалась · переподключаем бесплатный прокси…")
        publishState(
            STATE_CONNECTING,
            "Связь прервалась · переподключаем бесплатный прокси…",
        )

        cancelFreeRecoveryReset()
        stopFreeSessionRefresh()
        stopAutoMonitor()
        synchronized(lock) {
            tunFd?.runCatching { close() }
            tunFd = null
            worker = null
        }

        // tun2proxy must not be restarted inside the same :vpn process.
        // Keep the sticky foreground service started and recreate only this
        // isolated process; the new process gets a fresh gateway session.
        store.markVpnProcessRestartPending()
        mainHandler.postDelayed(
            { Process.killProcess(Process.myPid()) },
            PROCESS_HANDOFF_KILL_DELAY_MS,
        )
    }

    private fun stopTunnel() {
        store.clearVpnProcessRestartPending()
        cancelFreeRecoveryReset()
        stopFreeSessionRefresh()
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
        cancelFreeRecoveryReset()
        stopFreeSessionRefresh()
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
        store.clearVpnProcessRestartPending()
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
        sendBroadcast(
            Intent(this, PoolStateRelayReceiver::class.java)
                .setAction(ACTION_POOL_STATE)
                .putExtra(EXTRA_STATE, state)
                .putExtra(EXTRA_DETAIL, detail),
        )
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
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private data class SiteExclusionPlan(
        val enabled: Boolean,
        val bypassAddresses: List<InetAddress>,
        val dnsServers: List<InetAddress>,
        val dnsMode: TunnelDnsMode,
    ) {
        companion object {
            val EMPTY = SiteExclusionPlan(
                enabled = false,
                bypassAddresses = emptyList(),
                dnsServers = emptyList(),
                dnsMode = TunnelDnsMode.VIRTUAL,
            )
        }
    }

    private data class ReconcileSnapshot(
        val stopping: Boolean,
        val failoverHandoff: Boolean,
        val workerAlive: Boolean,
        val preflightAlive: Boolean,
        val tunPresent: Boolean,
        val prepared: PreparedProxy?,
    )

    private data class PreparedProxy(
        val resolved: ResolvedProxyProfile,
        val selectedProfile: ProxyProfile,
        val autoSelection: Boolean,
        val latencyMs: Long,
        val freeSessionExpiresAtEpochSeconds: Long? = null,
        val siteExclusions: SiteExclusionPlan = SiteExclusionPlan.EMPTY,
    )

    companion object {
        const val ACTION_CONNECT = "ru.arvectum.proxylauncher.CONNECT"
        const val ACTION_DISCONNECT = "ru.arvectum.proxylauncher.DISCONNECT"
        const val ACTION_RECONCILE = "ru.arvectum.proxylauncher.RECONCILE"
        const val INTERNAL_BROADCAST_PERMISSION =
            "ru.arvectum.proxylauncher.permission.INTERNAL_STATE"
        const val ACTION_STATE = "ru.arvectum.proxylauncher.STATE"
        const val ACTION_POOL_UPDATE = "ru.arvectum.proxylauncher.POOL_UPDATE"
        const val ACTION_POOL_STATE = "ru.arvectum.proxylauncher.POOL_STATE"
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
        private const val NETWORK_RECONCILE_DELAY_MS = 500L
        private const val PROCESS_HANDOFF_KILL_DELAY_MS = 300L
        private const val SWITCH_EVENT_WINDOW_MS = 30_000L
        private const val MAX_AUTO_ERROR_LENGTH = 520
        private const val ENGINE_START_FAILURE = -1000
    }
}
