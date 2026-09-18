package ru.arvectum.proxylauncher

import android.app.Activity
import android.app.AlertDialog
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Typeface
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import java.util.UUID
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType
import ru.arvectum.proxylauncher.storage.SecureProfileStore
import ru.arvectum.proxylauncher.tunnel.ProxyVpnService

class MainActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var profileSpinner: Spinner
    private lateinit var nameField: EditText
    private lateinit var hostField: EditText
    private lateinit var portField: EditText
    private lateinit var usernameField: EditText
    private lateinit var passwordField: EditText
    private lateinit var typeSpinner: Spinner
    private lateinit var newProfileButton: Button
    private lateinit var saveProfileButton: Button
    private lateinit var deleteProfileButton: Button
    private lateinit var connectButton: Button
    private lateinit var store: SecureProfileStore

    private var currentState = ProxyVpnService.STATE_DISCONNECTED
    private var currentProfileId: String? = null
    private var suppressProfileSelection = false
    private var profileChoices: List<ProfileChoice> = emptyList()

    private val proxyTypes = listOf(
        ProxyType.AUTO,
        ProxyType.HTTP,
        ProxyType.SOCKS5,
        ProxyType.HTTPS,
    )

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ProxyVpnService.ACTION_STATE) return
            renderState(
                intent.getStringExtra(ProxyVpnService.EXTRA_STATE) ?: ProxyVpnService.STATE_DISCONNECTED,
                intent.getStringExtra(ProxyVpnService.EXTRA_DETAIL),
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = SecureProfileStore(this)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(48, 72, 48, 48)
        }

        root.addView(TextView(this).apply {
            text = "Proxy Launcher"
            textSize = 28f
            setTypeface(typeface, Typeface.BOLD)
        })

        root.addView(TextView(this).apply {
            text = "Версия ${currentVersionName()}"
            textSize = 13f
            alpha = 0.68f
            setPadding(0, 4, 0, 0)
        })

        status = TextView(this).apply {
            textSize = 18f
            setPadding(0, 24, 0, 16)
        }
        root.addView(status)

        root.addView(TextView(this).apply {
            text = "Профиль"
            textSize = 14f
            alpha = 0.72f
        })

        profileSpinner = Spinner(this)
        root.addView(
            profileSpinner,
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
        )

        val profileActions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, 4, 0, 8)
        }
        newProfileButton = Button(this).apply {
            text = "НОВЫЙ"
            setOnClickListener { beginNewProfile() }
        }
        saveProfileButton = Button(this).apply {
            text = "СОХРАНИТЬ"
            setOnClickListener {
                saveCurrentProfile(showSavedMessage = true)
            }
        }
        deleteProfileButton = Button(this).apply {
            text = "УДАЛИТЬ"
            setOnClickListener { confirmDeleteCurrentProfile() }
        }
        profileActions.addView(newProfileButton, actionButtonParams())
        profileActions.addView(saveProfileButton, actionButtonParams())
        profileActions.addView(deleteProfileButton, actionButtonParams())
        root.addView(
            profileActions,
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
        )

        fun field(hint: String, inputType: Int = InputType.TYPE_CLASS_TEXT) = EditText(this).also {
            it.hint = hint
            it.inputType = inputType
            root.addView(
                it,
                ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
            )
        }

        nameField = field("Название профиля (необязательно)")
        hostField = field("Адрес прокси")
        portField = field("Порт", InputType.TYPE_CLASS_NUMBER)
        usernameField = field("Логин (необязательно)")
        passwordField = field(
            "Пароль (необязательно)",
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
        )

        typeSpinner = Spinner(this).apply {
            adapter = ArrayAdapter(
                this@MainActivity,
                android.R.layout.simple_spinner_dropdown_item,
                listOf(
                    "Авто: HTTP/HTTPS → SOCKS5 → HTTPS-proxy (TLS)",
                    "HTTP/HTTPS proxy (CONNECT)",
                    "SOCKS5",
                    "HTTPS-proxy с TLS",
                ),
            )
        }
        root.addView(
            typeSpinner,
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
        )

        root.addView(TextView(this).apply {
            text = "Авто использует один адрес, порт, логин и пароль. Обычный системный «HTTPS proxy» обычно работает через HTTP CONNECT; TLS до самого прокси проверяется отдельно в последнюю очередь."
            textSize = 14f
            setPadding(0, 8, 0, 20)
        })

        connectButton = Button(this).apply {
            textSize = 22f
            setOnClickListener {
                when (currentState) {
                    ProxyVpnService.STATE_CONNECTED,
                    ProxyVpnService.STATE_CONNECTING -> disconnectVpn()
                    ProxyVpnService.STATE_DISCONNECTING -> Unit
                    else -> saveProfileAndRequestVpnPermission()
                }
            }
        }
        root.addView(
            connectButton,
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
        )

        val scroll = ScrollView(this).apply {
            addView(
                root,
                ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
            )
        }
        setContentView(scroll)

        profileSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                if (suppressProfileSelection || currentState !in editableStates) return
                val choice = profileChoices.getOrNull(position) ?: return
                if (choice.id == null) {
                    beginNewProfile(updateSpinner = false)
                } else if (choice.id != currentProfileId) {
                    selectSavedProfile(choice.id)
                }
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        refreshProfileChoices(store.getActiveProfileId())
        renderState(store.getLastState(), store.getLastDetail())
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter(ProxyVpnService.ACTION_STATE)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(stateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(stateReceiver, filter)
        }
    }

    override fun onStop() {
        runCatching { unregisterReceiver(stateReceiver) }
        super.onStop()
    }

    private fun refreshProfileChoices(selectedId: String?) {
        val profiles = runCatching { store.listProfiles() }.getOrElse {
            renderState(ProxyVpnService.STATE_ERROR, "Не удалось прочитать сохранённые профили")
            emptyList()
        }
        profileChoices = buildList {
            add(ProfileChoice(null, "＋ Новый прокси"))
            profiles.forEach { add(ProfileChoice(it.id, it.name)) }
        }

        suppressProfileSelection = true
        profileSpinner.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            profileChoices,
        )
        val position = profileChoices.indexOfFirst { it.id == selectedId }.takeIf { it >= 0 } ?: 0
        profileSpinner.setSelection(position)
        suppressProfileSelection = false

        val id = profileChoices.getOrNull(position)?.id
        if (id == null) {
            clearProfileForm()
        } else {
            loadProfileIntoForm(id)
        }
        updateProfileControls()
    }

    private fun selectSavedProfile(id: String) {
        try {
            store.setActiveProfile(id)
            loadProfileIntoForm(id)
        } catch (_: Exception) {
            renderState(ProxyVpnService.STATE_ERROR, "Не удалось выбрать профиль")
        }
        updateProfileControls()
    }

    private fun loadProfileIntoForm(id: String) {
        val saved = runCatching { store.loadProfile(id) }.getOrNull() ?: run {
            renderState(ProxyVpnService.STATE_ERROR, "Не удалось прочитать профиль")
            return
        }
        currentProfileId = saved.profile.id
        nameField.setText(saved.profile.name)
        hostField.setText(saved.profile.host)
        portField.setText(saved.profile.port.toString())
        usernameField.setText(saved.profile.username.orEmpty())
        passwordField.setText(saved.password.orEmpty())
        typeSpinner.setSelection(proxyTypes.indexOf(saved.profile.type).coerceAtLeast(0))
    }

    private fun beginNewProfile(updateSpinner: Boolean = true) {
        if (currentState !in editableStates) return
        currentProfileId = null
        clearProfileForm()
        if (updateSpinner && profileChoices.isNotEmpty()) {
            suppressProfileSelection = true
            profileSpinner.setSelection(0)
            suppressProfileSelection = false
        }
        updateProfileControls()
    }

    private fun clearProfileForm() {
        currentProfileId = null
        nameField.setText("")
        hostField.setText("")
        portField.setText("")
        usernameField.setText("")
        passwordField.setText("")
        typeSpinner.setSelection(0)
    }

    private fun saveCurrentProfile(showSavedMessage: Boolean): Boolean {
        if (currentState !in editableStates) return false

        val host = hostField.text.toString().trim()
        val port = portField.text.toString().toIntOrNull()
        if (host.isBlank()) {
            renderState(ProxyVpnService.STATE_ERROR, "Введите адрес прокси")
            return false
        }
        if (port == null || port !in 1..65535) {
            renderState(ProxyVpnService.STATE_ERROR, "Порт должен быть от 1 до 65535")
            return false
        }

        val username = usernameField.text.toString().trim().takeIf { it.isNotBlank() }
        val password = if (username != null) passwordField.text.toString().toCharArray() else null
        val type = proxyTypes.getOrElse(typeSpinner.selectedItemPosition) { ProxyType.AUTO }
        val profileId = currentProfileId ?: "profile-${UUID.randomUUID()}"
        val profileName = nameField.text.toString().trim().ifBlank { "$host:$port" }
        val profile = ProxyProfile(
            id = profileId,
            name = profileName,
            host = host,
            port = port,
            type = type,
            username = username,
        )

        try {
            store.saveProfile(profile, password, makeActive = true)
        } catch (_: Exception) {
            renderState(ProxyVpnService.STATE_ERROR, "Не удалось безопасно сохранить профиль")
            return false
        } finally {
            password?.fill('\u0000')
        }

        currentProfileId = profileId
        refreshProfileChoices(profileId)
        if (showSavedMessage) {
            renderState(ProxyVpnService.STATE_DISCONNECTED, "Сохранено: $profileName")
        }
        return true
    }

    private fun confirmDeleteCurrentProfile() {
        val id = currentProfileId ?: return
        if (currentState !in editableStates) return
        val label = nameField.text.toString().trim().ifBlank { hostField.text.toString().trim() }
        AlertDialog.Builder(this)
            .setTitle("Удалить профиль?")
            .setMessage(label)
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Удалить") { _, _ -> deleteProfile(id) }
            .show()
    }

    private fun deleteProfile(id: String) {
        try {
            store.deleteProfile(id)
        } catch (_: Exception) {
            renderState(ProxyVpnService.STATE_ERROR, "Не удалось удалить профиль")
            return
        }
        val nextActiveId = store.getActiveProfileId()
        refreshProfileChoices(nextActiveId)
        renderState(ProxyVpnService.STATE_DISCONNECTED, "Профиль удалён")
    }

    private fun saveProfileAndRequestVpnPermission() {
        if (!saveCurrentProfile(showSavedMessage = false)) return

        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent != null) {
            renderState(ProxyVpnService.STATE_DISCONNECTED, "Разрешите создание VPN-подключения")
            @Suppress("DEPRECATION")
            startActivityForResult(permissionIntent, VPN_REQUEST)
        } else {
            connectVpn()
        }
    }

    private fun connectVpn() {
        renderState(ProxyVpnService.STATE_CONNECTING, "Проверяем прокси…")
        val intent = Intent(this, ProxyVpnService::class.java).setAction(ProxyVpnService.ACTION_CONNECT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun disconnectVpn() {
        renderState(ProxyVpnService.STATE_DISCONNECTING, "Отключение…")
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
        status.text = when (state) {
            ProxyVpnService.STATE_CONNECTING -> detail ?: "Подключение…"
            ProxyVpnService.STATE_CONNECTED -> detail ?: "Подключено"
            ProxyVpnService.STATE_DISCONNECTING -> detail ?: "Отключение…"
            ProxyVpnService.STATE_ERROR -> "Ошибка: ${detail ?: "не удалось подключиться"}"
            else -> detail ?: "Отключено"
        }
        connectButton.text = when (state) {
            ProxyVpnService.STATE_CONNECTED, ProxyVpnService.STATE_CONNECTING -> "ВЫКЛ"
            ProxyVpnService.STATE_DISCONNECTING -> "…"
            else -> "ВКЛ"
        }
        connectButton.isEnabled = state != ProxyVpnService.STATE_DISCONNECTING
        updateProfileControls()
    }

    private fun updateProfileControls() {
        val editable = currentState in editableStates
        profileSpinner.isEnabled = editable
        nameField.isEnabled = editable
        hostField.isEnabled = editable
        portField.isEnabled = editable
        usernameField.isEnabled = editable
        passwordField.isEnabled = editable
        typeSpinner.isEnabled = editable
        newProfileButton.isEnabled = editable
        saveProfileButton.isEnabled = editable
        deleteProfileButton.isEnabled = editable && currentProfileId != null
    }

    private fun actionButtonParams() =
        LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)

    private data class ProfileChoice(
        val id: String?,
        val label: String,
    ) {
        override fun toString(): String = label
    }

    companion object {
        private const val VPN_REQUEST = 1001
        private val editableStates = setOf(
            ProxyVpnService.STATE_DISCONNECTED,
            ProxyVpnService.STATE_ERROR,
        )
    }
}
