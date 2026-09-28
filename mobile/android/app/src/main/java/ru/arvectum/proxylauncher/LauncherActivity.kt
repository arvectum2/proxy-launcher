package ru.arvectum.proxylauncher

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import ru.arvectum.proxylauncher.ads.AppOpenAdGate

class LauncherActivity : Activity() {
    private var completed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = NAVY
        window.navigationBarColor = NAVY
        setContentView(buildSplash())
        AppOpenAdGate.open(this) { openMain() }
    }

    override fun onDestroy() {
        AppOpenAdGate.cancel(this)
        super.onDestroy()
    }

    private fun openMain() {
        runOnUiThread {
            if (completed || isFinishing || isDestroyed) return@runOnUiThread
            completed = true
            startActivity(Intent(this, MainActivity::class.java))
            finish()
        }
    }

    private fun buildSplash() =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(NAVY)
            setPadding(dp(32), dp(32), dp(32), dp(32))

            addView(
                TextView(this@LauncherActivity).apply {
                    text = "Arvectum"
                    textSize = 28f
                    setTextColor(MINT)
                    gravity = Gravity.CENTER
                },
            )
            addView(
                TextView(this@LauncherActivity).apply {
                    text = "Proxy Launcher"
                    textSize = 16f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                    setPadding(0, dp(8), 0, dp(20))
                },
            )
            addView(
                ProgressBar(this@LauncherActivity).apply {
                    isIndeterminate = true
                },
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
        }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        private val NAVY = Color.rgb(8, 26, 42)
        private val MINT = Color.rgb(87, 235, 194)
    }
}
