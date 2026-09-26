package ru.arvectum.proxylauncher

import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.RadioButton
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import ru.arvectum.proxylauncher.gateway.FreeGatewayClient
import ru.arvectum.proxylauncher.gateway.FreeProxyLocation
import ru.arvectum.proxylauncher.model.PrimaryRestorePolicy
import ru.arvectum.proxylauncher.model.ProxyHealthStatus
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType
import ru.arvectum.proxylauncher.routing.SiteExclusionPolicy
import ru.arvectum.proxylauncher.storage.PoolUiStateStore
import ru.arvectum.proxylauncher.storage.SecureProfileStore
import ru.arvectum.proxylauncher.tunnel.ProxyProtocolProbe
import ru.arvectum.proxylauncher.tunnel.ProxyVpnService
import ru.arvectum.proxylauncher.tunnel.TunnelResumeAction
import ru.arvectum.proxylauncher.tunnel.TunnelResumePolicy

class MainActivity : Activity() {
    private lateinit var profileSelectorShell: LinearLayout
    private lateinit var profileSelectionText: TextView
    private lateinit var newProfileButton: Button
    private lateinit var editProfileButton: Button
    private lateinit var connectButton: Button
    private lateinit var connectionDetail: TextView
    private lateinit var store: SecureProfileStore
    private lateinit var poolUiStore: PoolUiStateStore

    private val mainHandler = Handler(Looper.getMainLooper())
    private val freeGatewayClient = FreeGatewayClient()
    private var currentState = ProxyVpnService.STATE_DISCONNECTED
    private var currentProfileId: String? = null
    private var profileChoices: List<ProfileChoice> = emptyList()
    private var pendingSwitchChoice: ProfileChoice? = null
    private var pendingSwitchDetail: String? = null
    private var switchInProgress = false
    private var profilePopup: PopupWindow? = null
    private var freeLocations: List<FreeProxyLocation> = FreeGatewayClient.BOOTSTRAP_LOCATIONS
    private var freeLocationsLastFetchedAtMs = 0L
    private val freeLocationRetryRunnable = Runnable { refreshFreeLocations(force = true) }
    @Volatile private var freeLocationRefreshInProgress = false
    @Volatile private var healthScanInProgress = false

    private val proxyTypes = listOf(
        ProxyType.AUTO,
        ProxyType.HTTP,
        ProxyType.SOCKS5,
        ProxyType.HTTPS,
    )

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ProxyVpnService.ACTION_POOL_UPDATE -> {
                    val reopenMenu = profilePopup?.isShowing == true
                    if (reopenMenu) profilePopup?.dismiss()
                    refreshProfileChoices(currentSelectionKey())
                    if (reopenMenu) mainHandler.post { showProfileMenu() }
                }
                ProxyVpnService.ACTION_STATE -> {
                    val state = intent.getStringExtra(ProxyVpnService.EXTRA_STATE)
                        ?: ProxyVpnService.STATE_DISCONNECTED
                    val detail = intent.getStringExtra(ProxyVpnService.EXTRA_DETAIL)
                    renderState(state, detail)
                    handlePendingSwitchState(state, detail)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = SecureProfileStore(this)
        poolUiStore = PoolUiStateStore(this)

        window.statusBarColor = NAVY
        window.navigationBarColor = NAVY
        window.decorView.systemUiVisibility = 0

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(NAVY)
            setPadding(dp(18), dp(14), dp(18), dp(18))
        }

        root.addView(buildHeader())

        val powerArea = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        connectButton = buildPowerButton()
        powerArea.addView(
            connectButton,
            LinearLayout.LayoutParams(dp(powerDiameterDp()), dp(powerDiameterDp())),
        )

        connectionDetail = TextView(this).apply {
            textSize = 14f
            setTextColor(SOFT_GRAY)
            gravity = Gravity.CENTER
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(14), dp(16), dp(14), 0)
        }
        powerArea.addView(
            connectionDetail,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        root.addView(
            powerArea,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        root.addView(buildProfilePanel())

        setContentView(root)

        refreshProfileChoices(currentSelectionKey())
        renderState(
            poolUiStore.getTunnelState(ProxyVpnService.STATE_DISCONNECTED),
            poolUiStore.getTunnelDetail(),
        )
    }

    override fun onResume() {
        super.onResume()
        reconcileTunnelAfterResume()
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter(ProxyVpnService.ACTION_STATE).apply {
            addAction(ProxyVpnService.ACTION_POOL_UPDATE)
        }
        ContextCompat.registerReceiver(
            this,
            stateReceiver,
            filter,
            ProxyVpnService.INTERNAL_BROADCAST_PERMISSION,
            null,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        refreshFreeLocations(force = true)
        startProfileHealthScan()
    }

    override fun onStop() {
        runCatching { unregisterReceiver(stateReceiver) }
        mainHandler.removeCallbacks(freeLocationRetryRunnable)
        profilePopup?.dismiss()
        profilePopup = null
        super.onStop()
    }

    private fun buildHeader(): View =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(4), dp(4), dp(4), dp(8))

            val titleRow = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.BOTTOM
            }

            titleRow.addView(
                ImageView(this@MainActivity).apply {
                    setImageResource(R.drawable.arvectum_mark)
                    adjustViewBounds = true
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    contentDescription = "Arvectum"
                },
                LinearLayout.LayoutParams(dp(34), dp(23)),
            )

            titleRow.addView(
                TextView(this@MainActivity).apply {
                    text = getString(R.string.app_title)
                    textSize = 18f
                    setTextColor(MINT)
                    typeface = Typeface.create("sans-serif", Typeface.BOLD)
                    setSingleLine(true)
                    includeFontPadding = false
                    setAutoSizeTextTypeUniformWithConfiguration(
                        15,
                        18,
                        1,
                        TypedValue.COMPLEX_UNIT_SP,
                    )
                    setPadding(dp(7), 0, dp(8), 0)
                    gravity = Gravity.BOTTOM
                },
                LinearLayout.LayoutParams(
                    0,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    1f,
                ),
            )

            titleRow.addView(
                TextView(this@MainActivity).apply {
                    text = currentVersionName()
                    textSize = 11.5f
                    setTextColor(MINT_LIGHT)
                    alpha = 0.72f
                    includeFontPadding = false
                    gravity = Gravity.BOTTOM or Gravity.END
                },
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )

            addView(titleRow)
        }

    private fun buildPowerButton(): Button =
        Button(this).apply {
            isAllCaps = false
            text = "Подключиться"
            textSize = 21f
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            setSingleLine(true)
            maxLines = 1
            includeFontPadding = false
            setAutoSizeTextTypeUniformWithConfiguration(
                14,
                21,
                1,
                TypedValue.COMPLEX_UNIT_SP,
            )
            minWidth = 0
            minHeight = 0
            setPadding(dp(8), dp(12), dp(8), dp(12))
            elevation = dp(9).toFloat()
            background = powerRipple(GRAPHITE, SOFT_GRAY, MINT)
            setTextColor(WHITE)
            contentDescription = "Подключиться"
            setOnClickListener {
                when (currentState) {
                    ProxyVpnService.STATE_CONNECTED,
                    ProxyVpnService.STATE_CONNECTING -> disconnectVpn()
                    ProxyVpnService.STATE_DISCONNECTING -> Unit
                    else -> saveSelectionAndRequestVpnPermission()
                }
            }
            setOnTouchListener { view, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        view.animate()
                            .scaleX(0.965f)
                            .scaleY(0.965f)
                            .setDuration(70L)
                            .start()
                    }
                    MotionEvent.ACTION_UP -> {
                        view.animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .setDuration(120L)
                            .start()
                        view.performClick()
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        view.animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .setDuration(120L)
                            .start()
                    }
                }
                true
            }
        }

    private fun buildProfilePanel(): View {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = roundedSurface(GRAPHITE, null, 22f)
            elevation = dp(4).toFloat()
        }

        panel.addView(TextView(this).apply {
            text = "Прокси"
            textSize = 13f
            setTextColor(MINT_LIGHT)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(dp(2), 0, 0, dp(7))
        })

        profileSelectorShell = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(15), 0, dp(13), 0)
            background = roundedRipple(NAVY, MINT_RIPPLE, 14f, SOFT_GRAY)
            isClickable = true
            isFocusable = true
            contentDescription = "Выбрать прокси"
            setOnClickListener {
                if (isEnabled) showProfileMenu()
            }
        }
        profileSelectionText = TextView(this).apply {
            textSize = 17f
            setTextColor(WHITE)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        profileSelectorShell.addView(
            profileSelectionText,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        profileSelectorShell.addView(TextView(this).apply {
            text = "⌄"
            textSize = 25f
            setTextColor(MINT)
            gravity = Gravity.CENTER
            setPadding(dp(12), 0, 0, dp(3))
        })
        panel.addView(
            profileSelectorShell,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(56),
            ),
        )

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        newProfileButton = brandSmallButton("＋ Новый", ButtonTone.MINT).apply {
            setOnClickListener { showProfileEditor(null) }
        }
        editProfileButton = brandSmallButton("Изменить", ButtonTone.GHOST).apply {
            setOnClickListener {
                currentProfileId?.let(::showProfileEditor)
            }
        }
        actions.addView(
            newProfileButton,
            LinearLayout.LayoutParams(0, dp(48), 1f).apply {
                topMargin = dp(10)
            },
        )
        actions.addView(
            editProfileButton,
            LinearLayout.LayoutParams(0, dp(48), 1f).apply {
                leftMargin = dp(8)
                topMargin = dp(10)
            },
        )
        panel.addView(actions)

        return panel
    }

    private fun showProfileMenu() {
        refreshFreeLocations()
        if (profileChoices.isEmpty()) return

        val rows = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            background = roundedSurface(GRAPHITE, SOFT_GRAY, 14f)
        }
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            addView(rows)
        }
        val popupHeight = minOf(dp(390), dp(118) + profileChoices.size * dp(52))
        profilePopup?.dismiss()
        val popup = PopupWindow(
            scroll,
            profileSelectorShell.width,
            popupHeight,
            true,
        ).apply {
            isOutsideTouchable = true
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            elevation = dp(12).toFloat()
            inputMethodMode = PopupWindow.INPUT_METHOD_NOT_NEEDED
        }
        profilePopup = popup
        popup.setOnDismissListener {
            if (profilePopup === popup) profilePopup = null
        }

        val selectedKey = currentSelectionKey()
        val radioTint = ColorStateList(
            arrayOf(
                intArrayOf(android.R.attr.state_checked),
                intArrayOf(-android.R.attr.state_checked),
            ),
            intArrayOf(MINT, SOFT_GRAY),
        )

        val quickActions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        fun quickAction(label: String, onClick: () -> Unit): TextView =
            TextView(this).apply {
                text = label
                textSize = 12.5f
                setTextColor(MINT_LIGHT)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER
                setPadding(dp(8), 0, dp(8), 0)
                background = roundedRipple(GRAPHITE, MINT_RIPPLE, 10f)
                isClickable = true
                setOnClickListener {
                    popup.dismiss()
                    onClick()
                }
            }
        quickActions.addView(
            quickAction("Сайты") { showSiteExclusionsDialog() },
            LinearLayout.LayoutParams(0, dp(42), 1f),
        )
        quickActions.addView(
            quickAction("Приложения") { showAppExclusionsDialog() },
            LinearLayout.LayoutParams(0, dp(42), 1f).apply { leftMargin = dp(6) },
        )
        quickActions.addView(
            quickAction("Журнал") { showPoolEventsDialog() },
            LinearLayout.LayoutParams(0, dp(42), 1f).apply { leftMargin = dp(6) },
        )
        rows.addView(
            quickActions,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(42)).apply {
                bottomMargin = dp(6)
            },
        )

        profileChoices.forEach { choice ->
            rows.addView(
                RadioButton(this).apply {
                    text = choice.menuLabel
                    textSize = 16f
                    setTextColor(WHITE)
                    gravity = Gravity.CENTER_VERTICAL
                    isChecked = choice.key == selectedKey
                    buttonTintList = radioTint
                    minHeight = 0
                    minWidth = 0
                    setPadding(dp(10), 0, dp(12), 0)
                    background = roundedRipple(GRAPHITE, MINT_RIPPLE, 10f)
                    setOnClickListener {
                        popup.dismiss()
                        when {
                            currentState == ProxyVpnService.STATE_CONNECTED ||
                                currentState == ProxyVpnService.STATE_CONNECTING -> {
                                if (choice.key != currentSelectionKey()) {
                                    requestLiveSwitch(choice)
                                }
                            }
                            currentState == ProxyVpnService.STATE_DISCONNECTING ||
                                switchInProgress -> Unit
                            else -> applySelection(choice)
                        }
                    }
                },
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    dp(52),
                ),
            )
        }

        rows.addView(View(this).apply {
            setBackgroundColor(Color.argb(70, 200, 210, 220))
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)).apply {
            topMargin = dp(4)
            bottomMargin = dp(4)
        })

        val restoreToggle = CheckBox(this).apply {
            text = "Возвращать основной после восстановления"
            textSize = 13.5f
            setTextColor(WHITE)
            buttonTintList = ColorStateList(
                arrayOf(
                    intArrayOf(android.R.attr.state_checked),
                    intArrayOf(-android.R.attr.state_checked),
                ),
                intArrayOf(MINT, SOFT_GRAY),
            )
            isChecked = store.getRestorePolicy() == PrimaryRestorePolicy.RETURN_TO_PRIMARY
            isEnabled = currentState in editableStates && !switchInProgress
            alpha = if (isEnabled) 1f else 0.55f
            setPadding(dp(8), 0, dp(8), 0)
            setOnCheckedChangeListener { _, checked ->
                runCatching {
                    store.setRestorePolicy(
                        if (checked) PrimaryRestorePolicy.RETURN_TO_PRIMARY
                        else PrimaryRestorePolicy.STAY_ON_CURRENT,
                    )
                }
            }
        }
        rows.addView(
            restoreToggle,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(46)),
        )

        popup.showAsDropDown(profileSelectorShell, 0, dp(6))
    }

    private fun refreshFreeLocations(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force &&
            freeLocations.isNotEmpty() &&
            now - freeLocationsLastFetchedAtMs < FREE_LOCATION_REFRESH_MS
        ) return
        if (freeLocationRefreshInProgress) return

        freeLocationRefreshInProgress = true
        Thread({
            val result = runCatching { freeGatewayClient.listLocations() }
            mainHandler.post {
                val reopenMenu = profilePopup?.isShowing == true
                result.onSuccess { locations ->
                    freeLocations = locations
                    freeLocationsLastFetchedAtMs = System.currentTimeMillis()
                    mainHandler.removeCallbacks(freeLocationRetryRunnable)
                    if (reopenMenu) profilePopup?.dismiss()
                    refreshProfileChoices(currentSelectionKey())
                    if (reopenMenu) mainHandler.post { showProfileMenu() }
                }.onFailure {
                    if (freeLocations.isEmpty()) {
                        mainHandler.removeCallbacks(freeLocationRetryRunnable)
                        mainHandler.postDelayed(
                            freeLocationRetryRunnable,
                            FREE_LOCATION_RETRY_MS,
                        )
                    }
                }
                freeLocationRefreshInProgress = false
            }
        }, "APL-free-locations").start()
    }

    private fun refreshProfileChoices(selectedKey: String?) {
        val profiles = runCatching { store.listProfiles() }.getOrElse {
            renderState(ProxyVpnService.STATE_ERROR, "Не удалось прочитать сохранённые профили")
            emptyList()
        }
        val primaryId = runCatching { store.getPrimaryProfileId() }.getOrNull()
        val selectedFreeId = runCatching { store.getActiveFreeLocationId() }.getOrNull()
        val selectedFreeLabel = runCatching { store.getActiveFreeLocationLabel() }.getOrNull()
        val displayedFreeLocations = buildList {
            if (selectedFreeId != null && freeLocations.none { it.id == selectedFreeId }) {
                add(
                    FreeProxyLocation(
                        id = selectedFreeId,
                        label = selectedFreeLabel ?: "Бесплатный прокси",
                        countryCode = "",
                    ),
                )
            }
            addAll(freeLocations)
        }.distinctBy { it.id }
        val now = System.currentTimeMillis()
        profileChoices = buildList {
            displayedFreeLocations.forEach { location ->
                val profileId = "free:" + location.id
                val localHealth = runCatching { poolUiStore.getHealth(profileId) }.getOrNull()
                    ?.takeIf { now - it.checkedAtMs <= HEALTH_STALE_AFTER_MS }
                val suffix = when (localHealth?.status) {
                    ProxyHealthStatus.CHECKING -> " · проверяется"
                    ProxyHealthStatus.AVAILABLE ->
                        localHealth.latencyMs?.let { " · " + it + " мс" } ?: " · доступен"
                    ProxyHealthStatus.UNAVAILABLE -> " · недоступен"
                    else -> when (location.available) {
                        true -> location.latencyMs?.let { " · " + it + " мс" } ?: " · доступен"
                        false -> " · недоступен"
                        null -> ""
                    }
                }
                val label = location.label + " · бесплатно"
                add(
                    ProfileChoice(
                        key = FREE_KEY_PREFIX + location.id,
                        kind = ChoiceKind.FREE,
                        profileId = null,
                        label = label,
                        menuLabel = label + suffix,
                        freeLocationId = location.id,
                    ),
                )
            }
            add(ProfileChoice(AUTO_KEY, ChoiceKind.AUTO, null, "Авто", "Авто"))
            profiles.forEach { profile ->
                val health = runCatching { poolUiStore.getHealth(profile.id) }.getOrNull()
                val fresh = health?.takeIf { now - it.checkedAtMs <= HEALTH_STALE_AFTER_MS }
                val prefix = if (profile.id == primaryId) "★ " else ""
                val suffix = when (fresh?.status) {
                    ProxyHealthStatus.CHECKING -> " · проверяется"
                    ProxyHealthStatus.AVAILABLE -> fresh.latencyMs?.let { " · ${it} мс" } ?: " · доступен"
                    ProxyHealthStatus.UNAVAILABLE -> " · недоступен"
                    else -> ""
                }
                add(
                    ProfileChoice(
                        key = profile.id,
                        kind = ChoiceKind.PROFILE,
                        profileId = profile.id,
                        label = profile.name,
                        menuLabel = "$prefix${profile.name}$suffix",
                    ),
                )
            }
        }

        val choice = profileChoices.firstOrNull { it.key == selectedKey }
            ?: profileChoices.firstOrNull()
        if (choice == null) {
            profileSelectionText.text = "Нет доступных прокси"
            currentProfileId = null
        } else {
            profileSelectionText.text = choice.label
            currentProfileId = choice.profileId
        }
        updateProfileControls()
    }

    private fun startProfileHealthScan() {
        if (healthScanInProgress) return
        if (currentState == ProxyVpnService.STATE_CONNECTED ||
            currentState == ProxyVpnService.STATE_CONNECTING ||
            currentState == ProxyVpnService.STATE_DISCONNECTING
        ) return

        val profiles = runCatching { store.listProfiles() }.getOrDefault(emptyList())
        if (profiles.isEmpty()) return
        healthScanInProgress = true
        Thread({
            try {
                val probe = ProxyProtocolProbe()
                profiles.forEach { profile ->
                    poolUiStore.setHealth(profile.id, ProxyHealthStatus.CHECKING, null)
                    mainHandler.post { refreshProfileChoices(currentSelectionKey()) }
                    val resolved = runCatching { store.loadProfile(profile.id) }.getOrNull()
                    val measured = resolved?.let {
                        runCatching { probe.resolveMeasured(it.profile, it.password) }.getOrNull()
                    }
                    if (measured == null) {
                        poolUiStore.setHealth(profile.id, ProxyHealthStatus.UNAVAILABLE, null)
                    } else {
                        poolUiStore.setHealth(profile.id, ProxyHealthStatus.AVAILABLE, measured.latencyMs)
                    }
                    mainHandler.post { refreshProfileChoices(currentSelectionKey()) }
                }
            } finally {
                healthScanInProgress = false
            }
        }, "APL-profile-health").start()
    }

    private fun showSiteExclusionsDialog() {
        val entries = runCatching { store.getSiteExclusions() }.getOrDefault(emptyList()).toMutableList()
        val input = EditText(this).apply {
            hint = "example.com"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            setSingleLine(true)
            textSize = 15f
            setTextColor(NAVY)
            setHintTextColor(DISABLED_FG)
            setPadding(dp(13), dp(10), dp(13), dp(10))
            background = roundedSurface(WHITE, SOFT_GRAY, 11f)
        }
        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        fun renderEntries() {
            list.removeAllViews()
            if (entries.isEmpty()) {
                list.addView(TextView(this).apply {
                    text = "Список пока пуст"
                    textSize = 13f
                    setTextColor(DISABLED_FG)
                    setPadding(dp(4), dp(8), dp(4), dp(4))
                })
                return
            }
            entries.forEach { host ->
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(0, dp(3), 0, dp(3))
                }
                row.addView(TextView(this).apply {
                    text = host
                    textSize = 14f
                    setTextColor(NAVY)
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                row.addView(Button(this).apply {
                    text = "Удалить"
                    isAllCaps = false
                    setOnClickListener {
                        entries.remove(host)
                        renderEntries()
                    }
                })
                list.addView(row)
            }
        }

        fun addEntry() {
            val raw = input.text.toString()
            if (raw.isBlank()) return
            val normalized = try {
                SiteExclusionPolicy.normalize(raw)
            } catch (e: IllegalArgumentException) {
                input.error = e.message ?: "Проверьте адрес сайта"
                return
            }
            if (normalized == null) {
                input.error = "Введите адрес сайта"
                return
            }
            if (normalized !in entries) {
                entries.add(normalized)
                entries.sort()
            }
            input.setText("")
            input.error = null
            renderEntries()
        }

        val addButton = Button(this).apply {
            text = "Добавить"
            isAllCaps = false
            setOnClickListener { addEntry() }
        }
        val inputRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(input, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(addButton, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                marginStart = dp(8)
            })
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(4), dp(4), dp(4), 0)
            addView(TextView(this@MainActivity).apply {
                text = getString(R.string.site_exclusions_help)
                textSize = 13f
                setTextColor(GRAPHITE)
                setPadding(0, 0, 0, dp(10))
            })
            addView(inputRow)
            addView(list, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(8)
            })
        }
        renderEntries()

        val dialog = AlertDialog.Builder(this)
            .setTitle("Исключения")
            .setView(content)
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Сохранить", null)
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                if (input.text.toString().isNotBlank()) addEntry()
                val normalized = try {
                    SiteExclusionPolicy.normalizeAll(entries)
                } catch (e: IllegalArgumentException) {
                    input.error = e.message ?: "Проверьте список исключений"
                    return@setOnClickListener
                }
                try {
                    store.setSiteExclusions(normalized)
                } catch (_: Exception) {
                    input.error = "Не удалось сохранить исключения"
                    return@setOnClickListener
                }
                dialog.dismiss()
                if (currentState == ProxyVpnService.STATE_CONNECTED ||
                    currentState == ProxyVpnService.STATE_CONNECTING
                ) {
                    selectedChoice()?.let { requestLiveSwitch(it, "Применяем исключения…") }
                } else {
                    val detail = if (normalized.isEmpty()) "Исключения очищены"
                    else "Сохранено исключений: ${normalized.size}"
                    renderState(currentState, detail)
                }
            }
        }
        dialog.show()
    }

    private fun showAppExclusionsDialog() {
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = packageManager.queryIntentActivities(launcherIntent, 0)
            .mapNotNull { info ->
                val packageId = info.activityInfo?.packageName ?: return@mapNotNull null
                if (packageId == packageName) return@mapNotNull null
                val label = info.loadLabel(packageManager)?.toString()?.trim().orEmpty()
                InstalledApp(packageId, label.ifEmpty { packageId })
            }
            .distinctBy { it.packageId }
            .sortedWith(compareBy<InstalledApp> { it.label.lowercase(Locale.getDefault()) }.thenBy { it.packageId })

        if (apps.isEmpty()) {
            AlertDialog.Builder(this)
                .setTitle("Исключения приложений")
                .setMessage("Не удалось получить список установленных приложений.")
                .setPositiveButton("Закрыть", null)
                .show()
            return
        }

        val selected = runCatching { store.getAppExclusions().toMutableSet() }.getOrDefault(mutableSetOf())
        val labels = apps.map { it.label }.toTypedArray()
        val checked = BooleanArray(apps.size) { apps[it].packageId in selected }
        val dialog = AlertDialog.Builder(this)
            .setTitle("Исключения приложений")
            .setMultiChoiceItems(labels, checked) { _, index, enabled ->
                val packageId = apps[index].packageId
                if (enabled) selected.add(packageId) else selected.remove(packageId)
            }
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Сохранить", null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                try {
                    store.setAppExclusions(selected)
                } catch (_: Exception) {
                    renderState(ProxyVpnService.STATE_ERROR, "Не удалось сохранить исключения приложений")
                    return@setOnClickListener
                }
                dialog.dismiss()
                if (currentState == ProxyVpnService.STATE_CONNECTED ||
                    currentState == ProxyVpnService.STATE_CONNECTING
                ) {
                    selectedChoice()?.let { requestLiveSwitch(it, "Применяем исключения приложений…") }
                } else {
                    val count = store.getAppExclusions().size
                    val detail = if (count == 0) "Исключения приложений очищены"
                    else "Приложений в обход прокси: $count"
                    renderState(currentState, detail)
                }
            }
        }
        dialog.show()
    }

    private fun showPoolEventsDialog() {
        val events = runCatching { poolUiStore.listEvents(20) }.getOrDefault(emptyList())
        val formatter = SimpleDateFormat("dd.MM HH:mm:ss", Locale.getDefault())
        val message = if (events.isEmpty()) {
            "Журнал пока пуст"
        } else {
            events.joinToString("\n") { event ->
                val time = formatter.format(Date(event.timestampMs))
                val name = event.profileName?.let { " · $it" }.orEmpty()
                "$time · ${poolEventLabel(event.type)}$name"
            }
        }
        AlertDialog.Builder(this)
            .setTitle("Журнал")
            .setMessage(message)
            .setPositiveButton("Закрыть", null)
            .show()
    }

    private fun poolEventLabel(type: String): String = when (type) {
        "proxy unavailable" -> "прокси недоступен"
        "switched" -> "переключено"
        "restored" -> "основной восстановлен"
        "network changed" -> "смена сети"
        else -> type
    }

    private fun applySelection(choice: ProfileChoice): Boolean {
        return try {
            when (choice.kind) {
                ChoiceKind.AUTO -> {
                    if (store.listProfiles().isEmpty()) {
                        renderState(ProxyVpnService.STATE_ERROR, "Сначала добавьте хотя бы один прокси")
                        return false
                    }
                    store.setAutoProfileSelection(true)
                    currentProfileId = null
                }
                ChoiceKind.PROFILE -> {
                    val id = choice.profileId ?: return false
                    store.setActiveProfile(id)
                    currentProfileId = id
                }
                ChoiceKind.FREE -> {
                    val id = choice.freeLocationId ?: return false
                    store.setActiveFreeLocation(id, choice.label.removeSuffix(" · бесплатно"))
                    currentProfileId = null
                }
            }
            profileSelectionText.text = choice.label
            updateProfileControls()
            true
        } catch (_: Exception) {
            renderState(ProxyVpnService.STATE_ERROR, "Не удалось выбрать прокси")
            refreshProfileChoices(currentSelectionKey())
            false
        }
    }

    private fun requestLiveSwitch(
        choice: ProfileChoice,
        detail: String = "Переключаемся на ${choice.label}…",
    ) {
        pendingSwitchChoice = choice
        pendingSwitchDetail = detail
        switchInProgress = true
        profileSelectionText.text = choice.label
        renderState(ProxyVpnService.STATE_DISCONNECTING, detail)
        disconnectVpn(detail)
    }

    private fun handlePendingSwitchState(state: String, detail: String?) {
        if (!switchInProgress) return

        if (state == ProxyVpnService.STATE_DISCONNECTED) {
            val choice = pendingSwitchChoice ?: run {
                pendingSwitchDetail = null
                switchInProgress = false
                updateProfileControls()
                return
            }
            val reconnectDetail = pendingSwitchDetail ?: "Переключаемся на ${choice.label}…"
            mainHandler.postDelayed({
                if (!switchInProgress || pendingSwitchChoice?.key != choice.key) return@postDelayed
                if (applySelection(choice)) {
                    pendingSwitchChoice = null
                    pendingSwitchDetail = null
                    connectVpn(reconnectDetail)
                } else {
                    pendingSwitchChoice = null
                    pendingSwitchDetail = null
                    switchInProgress = false
                    updateProfileControls()
                }
            }, SWITCH_RECONNECT_DELAY_MS)
        } else if (state == ProxyVpnService.STATE_CONNECTED || state == ProxyVpnService.STATE_ERROR) {
            pendingSwitchChoice = null
            pendingSwitchDetail = null
            switchInProgress = false
            refreshProfileChoices(currentSelectionKey())
            renderState(state, detail)
        }
    }

    private fun currentSelectionKey(): String {
        val freeId = runCatching { store.getActiveFreeLocationId() }.getOrNull()
        if (freeId != null) return FREE_KEY_PREFIX + freeId
        return if (runCatching { store.isAutoProfileSelection() }.getOrDefault(false)) {
            AUTO_KEY
        } else {
            store.getActiveProfileId() ?: AUTO_KEY
        }
    }

    private fun selectedChoice(): ProfileChoice? =
        profileChoices.firstOrNull { it.key == currentSelectionKey() }

    private fun showProfileEditor(profileId: String?) {
        if (switchInProgress) return
        val creating = profileId == null
        val creatingWhileConnected = creating && currentState == ProxyVpnService.STATE_CONNECTED
        val editingWhileConnected = !creating && currentState == ProxyVpnService.STATE_CONNECTED
        if (creating) {
            if (currentState !in creatableStates) return
        } else if (currentState !in editableStates) {
            return
        }

        val existing = if (profileId == null) {
            null
        } else {
            runCatching { store.loadProfile(profileId) }.getOrNull()
        }

        val dialog = Dialog(this)
        val outer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(12), dp(18), dp(12))
            background = roundedSurface(WHITE, null, 22f)
        }

        outer.addView(TextView(this).apply {
            text = if (existing == null) "Новый прокси" else "Изменить профиль"
            textSize = 20f
            setTextColor(NAVY)
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
        })

        val fields = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(7), 0, 0)
        }

        val nameField = editorField(fields, "Название", "Например: Основной")
        val hostField = editorField(fields, "Адрес прокси", "proxy.example.com")
        val portField = editorField(
            fields,
            "Порт",
            "8000",
            InputType.TYPE_CLASS_NUMBER,
        )
        val usernameField = editorField(fields, "Логин", "Необязательно")
        val passwordField = editorField(
            fields,
            "Пароль",
            "Необязательно",
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
        )

        fields.addView(editorLabel("Протокол"))
        val typeSpinner = Spinner(this, Spinner.MODE_DROPDOWN).apply {
            adapter = ArrayAdapter(
                this@MainActivity,
                android.R.layout.simple_spinner_dropdown_item,
                listOf(
                    "Авто-протокол",
                    "HTTP/HTTPS (CONNECT)",
                    "SOCKS5",
                    "HTTPS-proxy с TLS",
                ),
            )
            setPadding(dp(12), 0, dp(10), 0)
            background = roundedSurface(WHITE, SOFT_GRAY, 12f)
        }
        fields.addView(
            typeSpinner,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(42),
            ).apply {
                topMargin = dp(3)
            },
        )

        val primaryId = runCatching { store.getPrimaryProfileId() }.getOrNull()
        val primaryCheck = CheckBox(this).apply {
            text = "Основной в Авто"
            textSize = 13.5f
            setTextColor(NAVY)
            buttonTintList = ColorStateList(
                arrayOf(
                    intArrayOf(android.R.attr.state_checked),
                    intArrayOf(-android.R.attr.state_checked),
                ),
                intArrayOf(MINT, SOFT_GRAY),
            )
            isChecked = existing?.profile?.id?.let { it == primaryId } ?: (primaryId == null)
            isEnabled = !creatingWhileConnected
            alpha = if (isEnabled) 1f else 0.55f
            setPadding(dp(3), 0, 0, 0)
        }
        fields.addView(
            primaryCheck,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(38)),
        )

        existing?.let {
            nameField.setText(it.profile.name)
            hostField.setText(it.profile.host)
            portField.setText(String.format(Locale.ROOT, "%d", it.profile.port))
            usernameField.setText(it.profile.username.orEmpty())
            passwordField.setText(it.password.orEmpty())
            typeSpinner.setSelection(proxyTypes.indexOf(it.profile.type).coerceAtLeast(0))
        }

        outer.addView(
            fields,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(9), 0, 0)
        }

        if (existing != null) {
            actions.addView(
                brandSmallButton("Удалить", ButtonTone.DANGER).apply {
                    isEnabled = !editingWhileConnected
                    alpha = if (isEnabled) 1f else 0.5f
                    setOnClickListener {
                        AlertDialog.Builder(this@MainActivity)
                            .setTitle("Удалить профиль?")
                            .setMessage(existing.profile.name)
                            .setNegativeButton("Отмена", null)
                            .setPositiveButton("Удалить") { _, _ ->
                                deleteProfile(existing.profile.id)
                                dialog.dismiss()
                            }
                            .show()
                    }
                },
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    dp(44),
                ),
            )
        }

        actions.addView(
            View(this),
            LinearLayout.LayoutParams(0, 1, 1f),
        )

        actions.addView(
            brandSmallButton("Отмена", ButtonTone.GHOST).apply {
                setOnClickListener { dialog.dismiss() }
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(44),
            ),
        )
        actions.addView(
            brandSmallButton("Сохранить", ButtonTone.MINT).apply {
                setOnClickListener {
                    val host = hostField.text.toString().trim()
                    val port = portField.text.toString().toIntOrNull()
                    if (host.isBlank()) {
                        hostField.error = "Введите адрес прокси"
                        return@setOnClickListener
                    }
                    if (port == null || port !in 1..65535) {
                        portField.error = "Порт 1–65535"
                        return@setOnClickListener
                    }

                    val username = usernameField.text.toString().trim().takeIf { it.isNotBlank() }
                    val password = if (username != null) {
                        passwordField.text.toString().toCharArray()
                    } else {
                        null
                    }
                    val type = proxyTypes.getOrElse(typeSpinner.selectedItemPosition) { ProxyType.AUTO }
                    val id = existing?.profile?.id ?: "profile-${UUID.randomUUID()}"
                    val name = nameField.text.toString().trim().ifBlank { "$host:$port" }

                    val profile = ProxyProfile(
                        id = id,
                        name = name,
                        host = host,
                        port = port,
                        type = type,
                        username = username,
                    )

                    try {
                        store.saveProfile(
                            profile,
                            password,
                            makeActive = !creatingWhileConnected,
                        )
                        if (!creatingWhileConnected) {
                            val currentPrimary = store.getPrimaryProfileId()
                            if (primaryCheck.isChecked || currentPrimary == null) {
                                store.setPrimaryProfileId(id)
                            } else if (currentPrimary == id) {
                                store.listProfiles()
                                    .firstOrNull { it.id != id }
                                    ?.let { store.setPrimaryProfileId(it.id) }
                            }
                        }
                    } catch (_: Exception) {
                        hostField.error = "Не удалось безопасно сохранить профиль"
                        return@setOnClickListener
                    } finally {
                        password?.fill('\u0000')
                    }

                    if (creatingWhileConnected) {
                        refreshProfileChoices(currentSelectionKey())
                    } else {
                        currentProfileId = id
                        refreshProfileChoices(id)
                        if (editingWhileConnected) {
                            profileChoices.firstOrNull { it.key == id }?.let {
                                requestLiveSwitch(it, "Применяем изменения профиля…")
                            }
                        } else {
                            renderState(ProxyVpnService.STATE_DISCONNECTED, "Сохранено: $name")
                        }
                    }
                    dialog.dismiss()
                }
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(44),
            ).apply {
                leftMargin = dp(7)
            },
        )

        outer.addView(actions)

        dialog.setContentView(outer)
        dialog.setCanceledOnTouchOutside(true)
        dialog.show()
        dialog.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            attributes = attributes.apply { dimAmount = 0.62f }
            setLayout(
                (resources.displayMetrics.widthPixels * 0.92f).toInt(),
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        }
    }

    private fun editorField(
        parent: LinearLayout,
        label: String,
        hint: String,
        inputType: Int = InputType.TYPE_CLASS_TEXT,
    ): EditText {
        parent.addView(editorLabel(label))
        return EditText(this).also {
            it.hint = hint
            it.inputType = inputType
            it.textSize = 15f
            it.setTextColor(NAVY)
            it.setHintTextColor(DISABLED_FG)
            it.setPadding(dp(13), 0, dp(13), 0)
            it.background = roundedSurface(WHITE, SOFT_GRAY, 11f)
            parent.addView(
                it,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    dp(42),
                ).apply {
                    topMargin = dp(3)
                    bottomMargin = dp(6)
                },
            )
        }
    }

    private fun editorLabel(text: String): TextView =
        TextView(this).apply {
            this.text = text
            textSize = 11.5f
            setTextColor(GRAPHITE)
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
        }

    private fun deleteProfile(id: String) {
        try {
            store.deleteProfile(id)
            poolUiStore.removeHealth(id)
        } catch (_: Exception) {
            renderState(ProxyVpnService.STATE_ERROR, "Не удалось удалить профиль")
            return
        }
        refreshProfileChoices(currentSelectionKey())
        renderState(ProxyVpnService.STATE_DISCONNECTED, "Профиль удалён")
    }

    private fun saveSelectionAndRequestVpnPermission() {
        val choice = selectedChoice()
        if (choice == null || !applySelection(choice)) return
        requestVpnPermissionOrConnect()
    }

    private fun requestVpnPermissionOrConnect() {
        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent != null) {
            renderState(ProxyVpnService.STATE_DISCONNECTED, "Разрешите создание VPN-подключения")
            @Suppress("DEPRECATION")
            startActivityForResult(permissionIntent, VPN_REQUEST)
        } else {
            connectVpn()
        }
    }

    private fun reconcileTunnelAfterResume() {
        val resumeState = currentState
        if (!TunnelResumePolicy.requiresVpnPermissionCheck(resumeState)) return

        val permissionGranted = runCatching { VpnService.prepare(this) == null }
            .getOrDefault(false)
        when (TunnelResumePolicy.decide(resumeState, permissionGranted)) {
            TunnelResumeAction.NONE -> Unit
            TunnelResumeAction.RECONCILE_SERVICE -> {
                startVpnService(ProxyVpnService.ACTION_RECONCILE)
            }
            TunnelResumeAction.RESET_FOR_PERMISSION -> {
                val detail = "Android сбросил разрешение VPN. Нажмите «Подключиться»."
                poolUiStore.setTunnelState(ProxyVpnService.STATE_DISCONNECTED, detail)
                renderState(ProxyVpnService.STATE_DISCONNECTED, detail)
            }
        }
    }

    private fun connectVpn(detail: String = "Проверяем прокси…") {
        renderState(ProxyVpnService.STATE_CONNECTING, detail)
        startVpnService(ProxyVpnService.ACTION_CONNECT)
    }

    private fun startVpnService(action: String) {
        val intent = Intent(this, ProxyVpnService::class.java).setAction(action)
        startForegroundService(intent)
    }

    private fun disconnectVpn(detail: String = "Отключение…") {
        renderState(ProxyVpnService.STATE_DISCONNECTING, detail)
        startService(Intent(this, ProxyVpnService::class.java).setAction(ProxyVpnService.ACTION_DISCONNECT))
    }

    @Deprecated("Legacy result API keeps the zero-dependency dogfood client small")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_REQUEST) return
        if (resultCode == RESULT_OK) {
            connectVpn()
        } else {
            renderState(ProxyVpnService.STATE_DISCONNECTED, "Разрешение VPN не выдано")
        }
    }

    private fun currentVersionName(): String = runCatching {
        if (Build.VERSION.SDK_INT >= 33) {
            packageManager
                .getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
                .versionName
                .orEmpty()
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0).versionName.orEmpty()
        }
    }.getOrDefault("—").ifBlank { "—" }

    private fun renderState(state: String, detail: String?) {
        currentState = state
        val displayDetail = compactConnectionDetail(state, detail)

        connectionDetail.text = displayDetail
        connectionDetail.setTextColor(
            when (state) {
                ProxyVpnService.STATE_CONNECTED -> MINT_LIGHT
                ProxyVpnService.STATE_ERROR -> ERROR_LIGHT
                else -> SOFT_GRAY
            },
        )

        connectButton.text = when {
            switchInProgress -> "Переключение"
            state == ProxyVpnService.STATE_CONNECTED -> "Подключено"
            state == ProxyVpnService.STATE_CONNECTING -> "Подключение"
            state == ProxyVpnService.STATE_DISCONNECTING -> "Отключение"
            else -> "Подключиться"
        }

        connectButton.contentDescription = connectButton.text
        connectButton.isEnabled =
            state != ProxyVpnService.STATE_DISCONNECTING && !switchInProgress

        val connected = state == ProxyVpnService.STATE_CONNECTED
        val connecting = state == ProxyVpnService.STATE_CONNECTING
        when {
            !connectButton.isEnabled -> {
                connectButton.setTextColor(SOFT_GRAY)
                connectButton.background = powerRipple(GRAPHITE, SOFT_GRAY, MINT_RIPPLE)
                connectButton.elevation = dp(4).toFloat()
            }
            connected -> {
                connectButton.setTextColor(MINT)
                connectButton.background = powerRipple(GRAPHITE, MINT, MINT_RIPPLE)
                connectButton.elevation = dp(10).toFloat()
            }
            connecting -> {
                connectButton.setTextColor(MINT_LIGHT)
                connectButton.background = powerRipple(GRAPHITE, MINT_LIGHT, MINT_RIPPLE)
                connectButton.elevation = dp(8).toFloat()
            }
            else -> {
                connectButton.setTextColor(WHITE)
                connectButton.background = powerRipple(GRAPHITE, SOFT_GRAY, MINT_RIPPLE)
                connectButton.elevation = dp(8).toFloat()
            }
        }

        updateProfileControls()
    }

    private fun compactConnectionDetail(state: String, detail: String?): String {
        if (switchInProgress) return "Меняем активный прокси"

        if (state == ProxyVpnService.STATE_ERROR) {
            return "Ошибка: ${detail ?: "не удалось подключиться"}"
        }

        if (state == ProxyVpnService.STATE_CONNECTED && detail != null) {
            val parts = simplifyConnectionDetail(detail).split(" · ")
            val useful = if (parts.firstOrNull()?.startsWith("Подключено") == true) {
                parts.drop(1)
            } else {
                parts
            }
            return useful.take(2).joinToString(" · ").ifBlank { "Соединение активно" }
        }

        if (state == ProxyVpnService.STATE_CONNECTING && !detail.isNullOrBlank()) {
            return simplifyConnectionDetail(detail)
                .removePrefix("Проверяем прокси…")
                .trim()
                .ifBlank { "Проверяем выбранный прокси" }
        }

        if (state == ProxyVpnService.STATE_DISCONNECTING) {
            return "Завершаем соединение"
        }

        val choice = profileChoices.firstOrNull { it.key == currentSelectionKey() }
        return choice?.label ?: "Выберите прокси"
    }

    private fun simplifyConnectionDetail(detail: String): String =
        detail
            .replace("HTTP/HTTPS (CONNECT)", "HTTP/HTTPS")
            .replace(". Создаём VPN…", "")
            .replace(". Создаём VPN...", "")
            .replace(" · Создаём VPN…", "")
            .replace(" · Создаём VPN...", "")
            .trim()

    private fun updateProfileControls() {
        val editable = currentState in editableStates && !switchInProgress
        val creatable = currentState in creatableStates && !switchInProgress
        val namedSelected = currentSelectionKey() != AUTO_KEY && currentProfileId != null

        profileSelectorShell.isEnabled =
            currentState != ProxyVpnService.STATE_DISCONNECTING && !switchInProgress
        profileSelectorShell.alpha = if (profileSelectorShell.isEnabled) 1f else 0.58f

        newProfileButton.isEnabled = creatable
        newProfileButton.alpha = if (creatable) 1f else 0.5f

        editProfileButton.visibility = if (namedSelected) View.VISIBLE else View.GONE
        editProfileButton.isEnabled = editable && namedSelected
        editProfileButton.alpha = if (editProfileButton.isEnabled) 1f else 0.5f
    }

    private fun brandSmallButton(text: String, tone: ButtonTone): Button =
        Button(this).apply {
            this.text = text
            isAllCaps = false
            textSize = 14f
            setTypeface(typeface, Typeface.BOLD)
            minHeight = 0
            minWidth = 0
            setPadding(dp(12), 0, dp(12), 0)
            when (tone) {
                ButtonTone.MINT -> {
                    setTextColor(NAVY)
                    background = roundedRipple(MINT, MINT_LIGHT, 12f)
                }
                ButtonTone.GHOST -> {
                    setTextColor(WHITE)
                    background = roundedRipple(GRAPHITE, MINT_RIPPLE, 12f, SOFT_GRAY)
                }
                ButtonTone.DANGER -> {
                    setTextColor(ERROR_FG)
                    background = roundedRipple(WHITE, ERROR_SOFT, 12f, ERROR_SOFT)
                }
            }
        }

    private fun roundedSurface(
        fill: Int,
        stroke: Int?,
        radiusDp: Float,
    ): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            cornerRadius = dp(radiusDp).toFloat()
            if (stroke != null) setStroke(dp(1), stroke)
        }

    private fun roundedRipple(
        fill: Int,
        ripple: Int,
        radiusDp: Float,
        stroke: Int? = null,
    ): RippleDrawable =
        RippleDrawable(
            ColorStateList.valueOf(ripple),
            roundedSurface(fill, stroke, radiusDp),
            null,
        )

    private fun powerRipple(fill: Int, stroke: Int, ripple: Int): RippleDrawable {
        val content = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(fill)
            setStroke(dp(3), stroke)
        }
        return RippleDrawable(ColorStateList.valueOf(ripple), content, null)
    }

    private fun powerDiameterDp(): Int {
        val heightDp = resources.displayMetrics.heightPixels / resources.displayMetrics.density
        return when {
            heightDp < 650f -> 150
            heightDp < 740f -> 164
            else -> 176
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private fun dp(value: Float): Int =
        (value * resources.displayMetrics.density).toInt()

    private data class InstalledApp(
        val packageId: String,
        val label: String,
    )

    private data class ProfileChoice(
        val key: String,
        val kind: ChoiceKind,
        val profileId: String?,
        val label: String,
        val menuLabel: String,
        val freeLocationId: String? = null,
    )

    private enum class ChoiceKind {
        AUTO,
        PROFILE,
        FREE,
    }

    private enum class ButtonTone {
        MINT,
        GHOST,
        DANGER,
    }

    companion object {
        private const val VPN_REQUEST = 1001
        private const val AUTO_KEY = "__auto_profile_selection__"
        private const val FREE_KEY_PREFIX = "__free_proxy__:"
        private const val SWITCH_RECONNECT_DELAY_MS = 700L
        private const val FREE_LOCATION_RETRY_MS = 5_000L
        private const val FREE_LOCATION_REFRESH_MS = 60_000L
        private const val HEALTH_STALE_AFTER_MS = 5 * 60 * 1000L

        private val NAVY = Color.parseColor("#001432")
        private val MINT = Color.parseColor("#00C8A0")
        private val MINT_LIGHT = Color.parseColor("#78FAE6")
        private val SOFT_GRAY = Color.parseColor("#C8D2DC")
        private val GRAPHITE = Color.parseColor("#283246")
        private val WHITE = Color.parseColor("#FFFFFF")
        private val DISABLED_FG = Color.parseColor("#96AAA6")
        private val ERROR_SOFT = Color.parseColor("#FDEAEA")
        private val ERROR_FG = Color.parseColor("#8A1C1C")
        private val ERROR_LIGHT = Color.parseColor("#FFB4B4")
        private val MINT_RIPPLE = Color.argb(72, 0, 200, 160)

        private val editableStates = setOf(
            ProxyVpnService.STATE_DISCONNECTED,
            ProxyVpnService.STATE_CONNECTED,
            ProxyVpnService.STATE_ERROR,
        )
        private val creatableStates = editableStates + ProxyVpnService.STATE_CONNECTED
    }
}
