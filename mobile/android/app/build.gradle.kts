plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val generatedBrandingRes = layout.buildDirectory.dir("generated/res/branding")
val generateBrandingResources = tasks.register<Copy>("generateBrandingResources") {
    val canonicalDesktopIcon = rootProject.file("../../assets/arvectum-icon-0.2.2-transparent.png")
    inputs.file(canonicalDesktopIcon)
    from(canonicalDesktopIcon)
    into(generatedBrandingRes.map { it.dir("drawable-nodpi") })
    rename { "arvectum_launcher.png" }
}

android {
    namespace = "ru.arvectum.proxylauncher"
    compileSdk = 35

    defaultConfig {
        applicationId = "ru.arvectum.proxylauncher"
        minSdk = 26
        targetSdk = 35
        versionCode = 6
        versionName = "0.1.5-dogfood"
    }

    signingConfigs {
        create("dogfood") {
            storeFile = file("../signing/proxy-launcher-dogfood.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("dogfood")
        }
    }

    sourceSets {
        getByName("main").res.srcDir(generatedBrandingRes)
    }
}

tasks.named("preBuild").configure {
    dependsOn(generateBrandingResources)
}

kotlin {
    jvmToolchain(17)
}
