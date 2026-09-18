import java.awt.RenderingHints
import java.awt.image.BufferedImage
import javax.imageio.ImageIO
import kotlin.math.roundToInt

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val generatedBrandingRes = layout.buildDirectory.dir("generated/res/branding")
val canonicalDesktopIcon = rootProject.file("../../assets/arvectum-icon-0.2.2-transparent.png")
val canonicalWordmark = rootProject.file("../../assets/arvectum-wordmark.png")
val generateBrandingResources = tasks.register("generateBrandingResources") {
    inputs.file(canonicalDesktopIcon)
    inputs.file(canonicalWordmark)
    outputs.file(generatedBrandingRes.map { it.file("drawable-nodpi/arvectum_launcher_foreground.png") })
    outputs.file(generatedBrandingRes.map { it.file("drawable-nodpi/arvectum_wordmark.png") })

    doLast {
        val source = ImageIO.read(canonicalDesktopIcon)
            ?: error("Unable to decode canonical Arvectum launcher icon")

        // Android adaptive icon:
        // the Deep Navy XML background fills the complete OEM mask.
        // Keep the whole canonical squircle/AV/globe inside a conservative circular safe zone
        // by scaling only the foreground artwork, never the background.
        val canvasSize = maxOf(source.width, source.height)
        val foregroundScale = 0.60
        val targetWidth = (source.width * foregroundScale).roundToInt()
        val targetHeight = (source.height * foregroundScale).roundToInt()
        val targetX = (canvasSize - targetWidth) / 2
        val targetY = (canvasSize - targetHeight) / 2

        val foreground = BufferedImage(canvasSize, canvasSize, BufferedImage.TYPE_INT_ARGB)
        val graphics = foreground.createGraphics()
        try {
            graphics.setRenderingHint(
                RenderingHints.KEY_INTERPOLATION,
                RenderingHints.VALUE_INTERPOLATION_BICUBIC,
            )
            graphics.setRenderingHint(
                RenderingHints.KEY_RENDERING,
                RenderingHints.VALUE_RENDER_QUALITY,
            )
            graphics.setRenderingHint(
                RenderingHints.KEY_ANTIALIASING,
                RenderingHints.VALUE_ANTIALIAS_ON,
            )
            graphics.drawImage(
                source,
                targetX,
                targetY,
                targetWidth,
                targetHeight,
                null,
            )
        } finally {
            graphics.dispose()
        }

        val foregroundTarget = generatedBrandingRes.get()
            .file("drawable-nodpi/arvectum_launcher_foreground.png")
            .asFile
        foregroundTarget.parentFile.mkdirs()
        check(ImageIO.write(foreground, "png", foregroundTarget)) {
            "Unable to encode Android adaptive launcher foreground"
        }

        val wordmark = ImageIO.read(canonicalWordmark)
            ?: error("Unable to decode canonical Arvectum wordmark")
        val wordmarkTarget = generatedBrandingRes.get()
            .file("drawable-nodpi/arvectum_wordmark.png")
            .asFile
        wordmarkTarget.parentFile.mkdirs()
        check(ImageIO.write(wordmark, "png", wordmarkTarget)) {
            "Unable to encode Android Arvectum wordmark"
        }
    }
}

android {
    namespace = "ru.arvectum.proxylauncher"
    compileSdk = 35

    defaultConfig {
        applicationId = "ru.arvectum.proxylauncher"
        minSdk = 26
        targetSdk = 35
        versionCode = 12
        versionName = "0.1.11-dogfood"
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
