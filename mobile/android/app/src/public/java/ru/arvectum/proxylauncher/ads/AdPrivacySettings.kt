package ru.arvectum.proxylauncher.ads

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import com.yandex.mobile.ads.common.YandexAds

object AdPrivacySettings {
    private const val PRIVACY_URL = "https://arvectum.com/privacy.html"

    fun show(activity: Activity) {
        val current =
            if (!AdPrivacyState.isChoiceRecorded(activity)) {
                "Выбор ещё не сохранён."
            } else if (AdPrivacyState.personalizedAdsConsent(activity)) {
                "Персонализация рекламы разрешена."
            } else {
                "Персонализация рекламы отключена."
            }

        AlertDialog.Builder(activity)
            .setTitle("Реклама и конфиденциальность")
            .setMessage(
                "$current\n\nМожно изменить выбор в любой момент. " +
                    "Отказ не отключает APL и не мешает подключению прокси.",
            )
            .setPositiveButton("Разрешить") { _, _ -> save(activity, true) }
            .setNegativeButton("Запретить") { _, _ -> save(activity, false) }
            .setNeutralButton("Политика") { _, _ ->
                runCatching {
                    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_URL)))
                }
            }
            .show()
    }

    private fun save(activity: Activity, consent: Boolean) {
        AdPrivacyState.save(activity, consent)
        YandexAds.setUserConsent(consent)
    }
}
