import java.awt.RenderingHints
import java.awt.image.BufferedImage
import javax.imageio.ImageIO
import kotlin.math.hypot
import kotlin.math.max
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
    outputs.file(generatedBrandingRes.map { it.file("drawable-nodpi/arvectum_mark.png") })

    doLast {
        val source = ImageIO.read(canonicalDesktopIcon)
            ?: error("Unable to decode canonical Arvectum launcher icon")
        val wordmark = ImageIO.read(canonicalWordmark)
            ?: error("Unable to decode canonical Arvectum wordmark")

        // Extract the canonical AV brand mark from the wordmark by taking the
        // first connected alpha run and stopping at the transparent gap before
        // the "Arvectum" lettering.
        val opaqueByColumn = BooleanArray(wordmark.width) { x ->
            (0 until wordmark.height).any { y ->
                ((wordmark.getRGB(x, y) ushr 24) and 0xFF) > 8
            }
        }
        val firstOpaque = opaqueByColumn.indexOfFirst { it }.coerceAtLeast(0)
        var markEnd = wordmark.width
        var gap = 0
        var seenMark = false
        for (x in firstOpaque until wordmark.width) {
            if (opaqueByColumn[x]) {
                seenMark = true
                gap = 0
            } else if (seenMark) {
                gap += 1
                if (gap >= 10) {
                    markEnd = x - gap + 1
                    break
                }
            }
        }
        val markWidth = max(1, markEnd - firstOpaque)
        val mark = wordmark.getSubimage(firstOpaque, 0, markWidth, wordmark.height)

        val markTarget = generatedBrandingRes.get()
            .file("drawable-nodpi/arvectum_mark.png")
            .asFile
        markTarget.parentFile.mkdirs()
        check(ImageIO.write(mark, "png", markTarget)) {
            "Unable to encode Android Arvectum brand mark"
        }

        // Match the visually successful 0.1.11 geometry: the complete canonical
        // desktop artwork is scaled to 60% and centered. Before scaling, strip
        // every desktop squircle/background pixel. Preserve only the Mint AV
        // artwork and the complete circular globe badge. The adaptive icon XML
        // supplies the one uniform Deep Navy background behind them.
        val cleaned = BufferedImage(source.width, source.height, BufferedImage.TYPE_INT_ARGB)
        val minSize = minOf(source.width, source.height).toDouble()
        val globeCenterX = source.width * 0.79
        val globeCenterY = source.height * 0.78
        val globeRadius = minSize * 0.135

        for (y in 0 until source.height) {
            for (x in 0 until source.width) {
                val argb = source.getRGB(x, y)
                val alpha = (argb ushr 24) and 0xFF
                if (alpha <= 8) continue

                val red = (argb ushr 16) and 0xFF
                val green = (argb ushr 8) and 0xFF
                val blue = argb and 0xFF
                val inGlobe = hypot(x - globeCenterX, y - globeCenterY) <= globeRadius
                val isMintLogo =
                    green >= 105 &&
                    blue >= 80 &&
                    green >= red + 30 &&
                    (green + blue) >= 245

                if (inGlobe || isMintLogo) {
                    cleaned.setRGB(x, y, argb)
                }
            }
        }

        val canvasSize = max(source.width, source.height)
        val foregroundScale = 0.60
        val targetWidth = (cleaned.width * foregroundScale).roundToInt()
        val targetHeight = (cleaned.height * foregroundScale).roundToInt()
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
                cleaned,
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
    }
}

android {
    namespace = "ru.arvectum.proxylauncher"
    compileSdk = 35

    defaultConfig {
        applicationId = "ru.arvectum.proxylauncher"
        minSdk = 26
        targetSdk = 35
        versionCode = 24
        versionName = "0.1.23"
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

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

kotlin {
    jvmToolchain(17)
}
