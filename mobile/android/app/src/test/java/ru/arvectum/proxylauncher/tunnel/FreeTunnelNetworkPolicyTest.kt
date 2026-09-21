package ru.arvectum.proxylauncher.tunnel

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FreeTunnelNetworkPolicyTest {
    @Test
    fun freeGatewayDoesNotRestartVpnOnPhysicalNetworkCallbacks() {
        assertFalse(FreeTunnelNetworkPolicy.requiresPhysicalNetworkHandoff(isFreeSession = true))
    }

    @Test
    fun normalProfilesKeepExistingNetworkHandoffBehavior() {
        assertTrue(FreeTunnelNetworkPolicy.requiresPhysicalNetworkHandoff(isFreeSession = false))
    }
}
