package ru.arvectum.proxylauncher.ads

import android.app.Activity
import android.app.AlertDialog
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
import java.util.WeakHashMap
import ru.arvectum.proxylauncher.BuildConfig

object AppOpenAdGate {
    private const val PREFS_NAME = "apl_ads"
    private const val KEY_LAUNCH_COUNT = "launch_count"
    private const val KEY_LAST_AD_SHOWN_AT_MS = "last_ad_shown_at_ms"
    private const val KEY_PRIVACY_CHOICE_RECORDED = "privacy_choice_recorded"
    private const val KEY_PERSONALIZED_ADS_CONSENT = "personalized_ads_consent"
    private const val DEMO_AD_UNIT_ID = "demo-appopenad-yandex"
    private const val PRODUCTION_AD_UNIT_ID = "R-M-20130429-1"
    private const val LOAD_TIMEOUT_MS = 1_500L

    private val sessions = WeakHashMap<Activity, Session>()

    fun open(activity: Activity, proceed: () -> Unit) {
        val prefs = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val decision = AppOpenAdPolicy.decide(
            previousLaunchCount = prefs.getInt(KEY_LAUNCH_COUNT, 0),
            lastAdShownAtMs = prefs.getLong(KEY_LAST_AD_SHOWN_AT_MS, 0L),
            nowMs = now,
            debugBuild = BuildConfig.DEBUG,
        )
        prefs.edit().putInt(KEY_LAUNCH_COUNT, decision.launchCount).apply()

        if (!decision.shouldAttemptAd) {
            proceed()
            return
        }

        val session = Session(activity, proceed)
        sessions[activity] = session
        session.start()
    }

    fun cancel(activity: Activity) {
        sessions.remove(activity)?.cancel()
    }

    private fun finish(activity: Activity, session: Session) {
        if (sessions[activity] !== session) return
        sessions.remove(activity)
        session.complete()
    }

    private class Session(
        private val activity: Activity,
        private val proceed: () -> Unit,
    ) {
        private val handler = Handler(Looper.getMainLooper())
        private var completed = false
        private var consentDialog: AlertDialog? = null
        private var adLoader: AppOpenAdLoader? = null
        private var appOpenAd: AppOpenAd? = null

        private val timeout = Runnable {
            finish(activity, this)
        }

        fun start() {
            val prefs = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(KEY_PRIVACY_CHOICE_RECORDED, false)) {
                showPrivacyChoice()
                return
            }
            startAds(prefs.getBoolean(KEY_PERSONALIZED_ADS_CONSENT, false))
        }

        private fun showPrivacyChoice() {
            if (completed || activity.isFinishing || activity.isDestroyed) {
                finish(activity, this)
                return
            }
            consentDialog = AlertDialog.Builder(activity)
                .setTitle("Реклама и конфиденциальность")
                .setMessage(
                    "Публичная версия APL использует Рекламную сеть Яндекса. " +
                        "Разрешить обработку рекламных идентификаторов для персонализации рекламы? " +
                        "При отказе APL продолжит работу, а реклама будет запрашиваться без такого согласия.",
                )
                .setPositiveButton("Разрешить") { _, _ -> recordChoiceAndStart(true) }
                .setNegativeButton("Отказаться") { _, _ -> recordChoiceAndStart(false) }
                .setOnCancelListener {
                    finish(activity, this)
                }
                .show()
        }

        private fun recordChoiceAndStart(consent: Boolean) {
            if (completed) return
            activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_PRIVACY_CHOICE_RECORDED, true)
                .putBoolean(KEY_PERSONALIZED_ADS_CONSENT, consent)
                .apply()
            startAds(consent)
        }

        private fun startAds(consent: Boolean) {
            if (completed) return
            YandexAds.setUserConsent(consent)
            handler.postDelayed(timeout, LOAD_TIMEOUT_MS)
            YandexAds.initialize(activity.applicationContext) {
                if (completed || sessions[activity] !== this) return@initialize
                val loader = AppOpenAdLoader(activity.application)
                adLoader = loader
                val adUnitId =
                    if (BuildConfig.DEBUG) DEMO_AD_UNIT_ID else PRODUCTION_AD_UNIT_ID
                loader.loadAd(
                    AdRequest.Builder(adUnitId).build(),
                    object : AppOpenAdLoadListener {
                        override fun onAdLoaded(ad: AppOpenAd) {
                            if (completed || sessions[activity] !== this@Session) {
                                ad.setAdEventListener(null)
                                return
                            }
                            handler.removeCallbacks(timeout)
                            appOpenAd = ad
                            ad.setAdEventListener(
                                object : AppOpenAdEventListener {
                                    override fun onAdShown() {
                                        activity
                                            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                                            .edit()
                                            .putLong(KEY_LAST_AD_SHOWN_AT_MS, System.currentTimeMillis())
                                            .apply()
                                    }

                                    override fun onAdFailedToShow(adError: AdError) {
                                        finish(activity, this@Session)
                                    }

                                    override fun onAdDismissed() {
                                        finish(activity, this@Session)
                                    }

                                    override fun onAdClicked() = Unit

                                    override fun onAdImpression(impressionData: ImpressionData?) = Unit
                                },
                            )
                            runCatching { ad.show(activity) }
                                .onFailure { finish(activity, this@Session) }
                        }

                        override fun onAdFailedToLoad(adRequestError: AdRequestError) {
                            finish(activity, this@Session)
                        }
                    },
                )
            }
        }

        fun cancel() {
            if (completed) return
            completed = true
            handler.removeCallbacks(timeout)
            consentDialog?.dismiss()
            consentDialog = null
            appOpenAd?.setAdEventListener(null)
            appOpenAd = null
            adLoader = null
        }

        fun complete() {
            if (completed) return
            completed = true
            handler.removeCallbacks(timeout)
            consentDialog?.dismiss()
            consentDialog = null
            appOpenAd?.setAdEventListener(null)
            appOpenAd = null
            adLoader = null
            proceed()
        }
    }
}
