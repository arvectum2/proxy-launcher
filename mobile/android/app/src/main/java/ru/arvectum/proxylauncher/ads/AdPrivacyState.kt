package ru.arvectum.proxylauncher.ads

import android.content.Context

object AdPrivacyState {
    private const val PREFS_NAME = "apl_ads"
    private const val KEY_PRIVACY_CHOICE_RECORDED = "privacy_choice_recorded"
    private const val KEY_PERSONALIZED_ADS_CONSENT = "personalized_ads_consent"

    fun isChoiceRecorded(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_PRIVACY_CHOICE_RECORDED, false)

    fun personalizedAdsConsent(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_PERSONALIZED_ADS_CONSENT, false)

    fun save(context: Context, consent: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PRIVACY_CHOICE_RECORDED, true)
            .putBoolean(KEY_PERSONALIZED_ADS_CONSENT, consent)
            .apply()
    }
}
