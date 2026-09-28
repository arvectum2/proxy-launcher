package ru.arvectum.proxylauncher

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import ru.arvectum.proxylauncher.ads.LaunchAdGate

class LauncherActivity : Activity() {
    private lateinit var launchAdGate: LaunchAdGate
    private var openedMain = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.statusBarColor = NAVY
        window.navigationBarColor = NAVY
        setContentView(buildSplash())

        launchAdGate = LaunchAdGate(this) {
            openMain()
        }
        launchAdGate.start()
    }

    override fun onDestroy() {
        if (::launchAdGate.isInitialized) {
            launchAdGate.destroy()
        }
        super.onDestroy()
    }

    private fun openMain() {
        if (openedMain || isFinishing || isDestroyed) return
        openedMain = true
        startActivity(Intent(this, MainActivity::class.java))
        finish()
    }

    private fun buildSplash(): FrameLayout =
        FrameLayout(this).apply {
            setBackgroundColor(NAVY)

            addView(
                ImageView(this@LauncherActivity).apply {
                    setImageResource(R.mipmap.arvectum_launcher)
                    contentDescription = "Arvectum"
                },
                FrameLayout.LayoutParams(dp(112), dp(112), Gravity.CENTER).apply {
                    bottomMargin = dp(76)
                },
            )

            addView(
                TextView(this@LauncherActivity).apply {
                    text = "Proxy Launcher"
                    textSize = 20f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                },
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER,
                ).apply {
                    topMargin = dp(90)
                },
            )

            addView(
                ProgressBar(this@LauncherActivity).apply {
                    isIndeterminate = true
                },
                FrameLayout.LayoutParams(dp(32), dp(32), Gravity.CENTER).apply {
                    topMargin = dp(164)
                },
            )
        }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        private val NAVY = Color.parseColor("#001432")
    }
}
