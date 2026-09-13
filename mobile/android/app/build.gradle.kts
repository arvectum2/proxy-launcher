plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "ru.arvectum.proxylauncher"
    compileSdk = 35

    defaultConfig {
        applicationId = "ru.arvectum.proxylauncher"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0-dev"
    }
}

kotlin {
    jvmToolchain(17)
}
