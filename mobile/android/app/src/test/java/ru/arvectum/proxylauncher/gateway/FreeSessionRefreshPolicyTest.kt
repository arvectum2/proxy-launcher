package ru.arvectum.proxylauncher.gateway

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FreeSessionRefreshPolicyTest {
    @Test
    fun schedulesRefreshBeforeExpiry() {
        val delay = FreeSessionRefreshPolicy.delayMillis(1_000, 4_600)
        assertEquals(3_300_000L, delay)
        assertTrue(FreeSessionRefreshPolicy.delayMillis(4_500, 4_600) >= 1_000L)
    }
}
