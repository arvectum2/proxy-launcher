package ru.arvectum.proxylauncher.ui

data class ProfileActionMetrics(
    val panelHorizontalPaddingDp: Int,
    val rowTopPaddingDp: Int,
    val rowBottomPaddingDp: Int,
    val gapDp: Int,
    val actionHeightDp: Int,
    val horizontalTextPaddingDp: Int,
    val minTextSp: Int,
    val maxTextSp: Int,
    val cornerRadiusDp: Float,
)

object ResponsiveUiPolicy {
    fun profileActionMetrics(
        screenWidthDp: Int,
        screenHeightDp: Int,
        fontScale: Float,
    ): ProfileActionMetrics {
        val narrow = screenWidthDp in 1..359
        val short = screenHeightDp in 1..639
        val largeText = fontScale >= 1.15f
        val veryLargeText = fontScale >= 1.30f

        return ProfileActionMetrics(
            panelHorizontalPaddingDp = if (narrow) 12 else 16,
            rowTopPaddingDp = if (short) 6 else 8,
            rowBottomPaddingDp = if (short) 6 else 8,
            gapDp = if (narrow) 6 else 8,
            actionHeightDp = 48,
            horizontalTextPaddingDp = if (narrow || largeText) 6 else 10,
            minTextSp = if (veryLargeText || narrow) 10 else 11,
            maxTextSp = when {
                veryLargeText -> 12
                narrow || largeText -> 13
                else -> 14
            },
            cornerRadiusDp = if (narrow) 11f else 12f,
        )
    }
}
