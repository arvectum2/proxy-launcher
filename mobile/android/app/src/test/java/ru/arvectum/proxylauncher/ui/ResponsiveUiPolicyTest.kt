package ru.arvectum.proxylauncher.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ResponsiveUiPolicyTest {
    @Test
    fun normalPhoneKeepsReadableFourteenSpActions() {
        val metrics = ResponsiveUiPolicy.profileActionMetrics(
            screenWidthDp = 411,
            screenHeightDp = 820,
            fontScale = 1.0f,
        )

        assertEquals(48, metrics.actionHeightDp)
        assertEquals(14, metrics.maxTextSp)
        assertEquals(8, metrics.gapDp)
        assertEquals(16, metrics.panelHorizontalPaddingDp)
    }

    @Test
    fun narrowPhoneReclaimsWidthWithoutShrinkingTouchTarget() {
        val metrics = ResponsiveUiPolicy.profileActionMetrics(
            screenWidthDp = 320,
            screenHeightDp = 640,
            fontScale = 1.0f,
        )

        assertEquals(48, metrics.actionHeightDp)
        assertEquals(12, metrics.panelHorizontalPaddingDp)
        assertEquals(6, metrics.gapDp)
        assertEquals(6, metrics.horizontalTextPaddingDp)
        assertTrue(metrics.minTextSp >= 10)
    }

    @Test
    fun largeFontScaleReducesLabelCeilingButKeepsTouchTarget() {
        val metrics = ResponsiveUiPolicy.profileActionMetrics(
            screenWidthDp = 360,
            screenHeightDp = 720,
            fontScale = 1.35f,
        )

        assertEquals(48, metrics.actionHeightDp)
        assertEquals(12, metrics.maxTextSp)
        assertEquals(10, metrics.minTextSp)
    }

    @Test
    fun shortScreenReducesOnlyVerticalWhitespace() {
        val metrics = ResponsiveUiPolicy.profileActionMetrics(
            screenWidthDp = 360,
            screenHeightDp = 600,
            fontScale = 1.0f,
        )

        assertEquals(6, metrics.rowTopPaddingDp)
        assertEquals(6, metrics.rowBottomPaddingDp)
        assertEquals(48, metrics.actionHeightDp)
    }
}
