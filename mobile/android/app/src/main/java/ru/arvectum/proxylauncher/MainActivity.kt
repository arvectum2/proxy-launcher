package ru.arvectum.proxylauncher

import android.app.Activity
import android.content.Intent
import android.graphics.Typeface
import android.net.VpnService
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.ArrayAdapter
import android.widget.TextView

class MainActivity : Activity() {
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

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

        status = TextView(this).apply {
            text = "Отключено"
            textSize = 18f
            setPadding(0, 24, 0, 24)
        }
        root.addView(status)

        fun field(hint: String, inputType: Int = android.text.InputType.TYPE_CLASS_TEXT) = EditText(this).also {
            it.hint = hint
            it.inputType = inputType
            root.addView(it, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }

        field("Адрес прокси")
        field("Порт", android.text.InputType.TYPE_CLASS_NUMBER)
        field("Логин (необязательно)")
        field("Пароль (необязательно)", android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD)

        root.addView(Spinner(this).apply {
            adapter = ArrayAdapter(this@MainActivity, android.R.layout.simple_spinner_dropdown_item, listOf("SOCKS5", "HTTP"))
        }, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        root.addView(Button(this).apply {
            text = "ВКЛ"
            textSize = 22f
            setOnClickListener { requestVpnPermission() }
        }, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        setContentView(root)
    }

    private fun requestVpnPermission() {
        val intent: Intent? = VpnService.prepare(this)
        if (intent != null) {
            status.text = "Нужно разрешение VPN"
            startActivityForResult(intent, VPN_REQUEST)
        } else {
            status.text = "VPN разрешён — подключаем движок на следующем шаге"
        }
    }

    @Deprecated("Legacy result API is sufficient for the zero-dependency spike")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST) {
            status.text = if (resultCode == RESULT_OK) "VPN разрешён — движок ещё не подключён" else "Разрешение VPN не выдано"
        }
    }

    companion object { private const val VPN_REQUEST = 1001 }
}
