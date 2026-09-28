package ru.arvectum.proxylauncher.ads

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yandex.mobile.ads.appopenad.AppOpenAd
import com.yandex.mobile.ads.appopenad.AppOpenAdEventListener
import com.yandex.mobile.ads.appopenad.AppOpenAdLoadListener
import com.yandex.mobile.ads.appopenad.AppOpenAdLoader
import com.yandex.mobile.ads.common.AdError
import com.yandex.mobile.ads.common.AdRequest
import com.yandex.mobile.ads.common.AdRequestError
import com.yandex.mobile.ads.common.ImpressionData
import com.yandex.mobile.ads.common.YandexAds
import ru.arvectum.proxylauncher.BuildConfig

class LaunchAdGate(
    private val activity: Activity,
    private val onComplete: () -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val preferences =
        activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private var completed = false
    private var loading = false
    private var loader: AppOpenAdLoader? = null
    private var appOpenAd: AppOpenAd? = null

    private val timeoutRunnable = Runnable {
        complete()
    }

    fun start() {
        if (!BuildConfig.ADS_ENABLED) {
            complete()
            return
        }

        val launchCount = preferences.getInt(KEY_LAUNCH_COUNT, 0) + 1
        preferences.edit().putInt(KEY_LAUNCH_COUNT, launchCount).apply()

        val now = System.currentTimeMillis()
        val lastShownAt = preferences.getLong(KEY_LAST_SHOWN_AT, 0L)
        if (!AdDisplayPolicy.shouldAttempt(launchCount, lastShownAt, now)) {
            complete()
            return
        }

        handler.postDelayed(timeoutRunnable, LOAD_TIMEOUT_MS)

        YandexAds.initialize(activity.applicationContext) {
            if (completed || activity.isFinishing || activity.isDestroyed) return@initialize
            loadAd()
        }
    }

    fun destroy() {
        handler.removeCallbacks(timeoutRunnable)
        loader?.cancelLoading()
        clearAd()
        loader = null
    }

    private fun loadAd() {
        if (loading || completed) return
        loading = true

        val adUnitId = if (BuildConfig.DEBUG) {
            DEMO_AD_UNIT_ID
        } else {
            BuildConfig.YANDEX_APP_OPEN_AD_UNIT_ID
        }

        val adLoader = AppOpenAdLoader(activity.application)
        loader = adLoader
        adLoader.loadAd(
            AdRequest.Builder(adUnitId).build(),
            object : AppOpenAdLoadListener {
                override fun onAdLoaded(appOpenAd: AppOpenAd) {
                    loading = false
                    if (completed || activity.isFinishing || activity.isDestroyed) {
                        appOpenAd.setAdEventListener(null)
                        return
                    }

                    handler.removeCallbacks(timeoutRunnable)
                    this@LaunchAdGate.appOpenAd = appOpenAd
                    appOpenAd.setAdEventListener(adEventListener)
                    runCatching { appOpenAd.show(activity) }
                        .onFailure { complete() }
                }

                override fun onAdFailedToLoad(adRequestError: AdRequestError) {
                    loading = false
                    complete()
                }
            },
        )
    }

    private val adEventListener = object : AppOpenAdEventListener {
        override fun onAdShown() {
            preferences.edit()
                .putLong(KEY_LAST_SHOWN_AT, System.currentTimeMillis())
                .apply()
        }

        override fun onAdFailedToShow(adError: AdError) {
            clearAd()
            complete()
        }

        override fun onAdDismissed() {
            clearAd()
            complete()
        }

        override fun onAdClicked() = Unit

        override fun onAdImpression(impressionData: ImpressionData?) = Unit
    }

    private fun clearAd() {
        appOpenAd?.setAdEventListener(null)
        appOpenAd = null
    }

    private fun complete() {
        if (completed) return
        completed = true
        handler.removeCallbacks(timeoutRunnable)
        loader?.cancelLoading()
        loading = false
        clearAd()
        onComplete()
    }

    companion object {
        private const val PREFS_NAME = "apl_ads"
        private const val KEY_LAUNCH_COUNT = "launch_count"
        private const val KEY_LAST_SHOWN_AT = "last_shown_at_ms"
        private const val DEMO_AD_UNIT_ID = "demo-appopenad-yandex"
        private const val LOAD_TIMEOUT_MS = 1_500L
    }
}
