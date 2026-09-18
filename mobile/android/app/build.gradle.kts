import java.awt.RenderingHints
import java.awt.geom.Ellipse2D
import java.awt.image.BufferedImage
import javax.imageio.ImageIO
import kotlin.math.max
import kotlin.math.min
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

        // Launcher foreground: do not reuse the desktop squircle background.
        // The Android adaptive background already supplies full-bleed Deep Navy.
        // Compose only the clean AV mark plus the circular globe badge, so no
        // square/squircle seams can remain inside the launcher circle.
        val canvasSize = max(source.width, source.height)
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

            val avTargetWidth = (canvasSize * 0.56).roundToInt()
            val avTargetHeight = (mark.height * (avTargetWidth.toDouble() / mark.width)).roundToInt()
            val avX = ((canvasSize - avTargetWidth) * 0.43).roundToInt()
            val avY = (canvasSize * 0.23).roundToInt()
            graphics.drawImage(mark, avX, avY, avTargetWidth, avTargetHeight, null)

            // Extract the product globe badge from the canonical desktop icon
            // with a circular clip; surrounding squircle pixels are excluded.
            val srcDiameter = (min(source.width, source.height) * 0.34).roundToInt()
            val srcCenterX = (source.width * 0.79).roundToInt()
            val srcCenterY = (source.height * 0.78).roundToInt()
            val srcX = (srcCenterX - srcDiameter / 2).coerceIn(0, source.width - srcDiameter)
            val srcY = (srcCenterY - srcDiameter / 2).coerceIn(0, source.height - srcDiameter)

            val badgeDiameter = (canvasSize * 0.20).roundToInt()
            val badgeX = (canvasSize * 0.66).roundToInt()
            val badgeY = (canvasSize * 0.61).roundToInt()
            val oldClip = graphics.clip
            graphics.clip = Ellipse2D.Double(
                badgeX.toDouble(),
                badgeY.toDouble(),
                badgeDiameter.toDouble(),
                badgeDiameter.toDouble(),
            )
            graphics.drawImage(
                source,
                badgeX,
                badgeY,
                badgeX + badgeDiameter,
                badgeY + badgeDiameter,
                srcX,
                srcY,
                srcX + srcDiameter,
                srcY + srcDiameter,
                null,
            )
            graphics.clip = oldClip
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
        versionCode = 13
        versionName = "0.1.12"
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
