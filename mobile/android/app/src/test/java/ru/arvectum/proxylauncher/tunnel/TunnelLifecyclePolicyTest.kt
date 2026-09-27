package ru.arvectum.proxylauncher.tunnel

import org.junit.Assert.assertEquals
import org.junit.Test

class TunnelLifecyclePolicyTest {
    @Test
    fun connectedAndConnectingStatesReconcileWhenVpnGrantExists() {
        assertEquals(
            TunnelResumeAction.RECONCILE_SERVICE,
            TunnelResumePolicy.decide(ProxyVpnService.STATE_CONNECTED, vpnPermissionGranted = true),
        )
        assertEquals(
            TunnelResumeAction.RECONCILE_SERVICE,
            TunnelResumePolicy.decide(ProxyVpnService.STATE_CONNECTING, vpnPermissionGranted = true),
        )
    }

    @Test
    fun intentionallyOffStatesNeverTouchVpnPreparationOrAutoStartOnResume() {
        listOf(
            ProxyVpnService.STATE_DISCONNECTED,
            ProxyVpnService.STATE_ERROR,
        ).forEach { state ->
            assertEquals(false, TunnelResumePolicy.requiresVpnPermissionCheck(state))
            assertEquals(
                TunnelResumeAction.NONE,
                TunnelResumePolicy.decide(state, vpnPermissionGranted = true),
            )
        }
    }

    @Test
    fun activeOrInterruptedDisconnectStatesMayInspectVpnPermission() {
        assertEquals(
            true,
            TunnelResumePolicy.requiresVpnPermissionCheck(ProxyVpnService.STATE_CONNECTED),
        )
        assertEquals(
            true,
            TunnelResumePolicy.requiresVpnPermissionCheck(ProxyVpnService.STATE_CONNECTING),
        )
        assertEquals(
            true,
            TunnelResumePolicy.requiresVpnPermissionCheck(ProxyVpnService.STATE_DISCONNECTING),
        )
    }

    @Test
    fun staleDisconnectingAlwaysResetsWithoutRestartingTunnel() {
        assertEquals(
            TunnelResumeAction.RESET_STALE_DISCONNECTING,
            TunnelResumePolicy.decide(
                ProxyVpnService.STATE_DISCONNECTING,
                vpnPermissionGranted = true,
            ),
        )
        assertEquals(
            TunnelResumeAction.RESET_STALE_DISCONNECTING,
            TunnelResumePolicy.decide(
                ProxyVpnService.STATE_DISCONNECTING,
                vpnPermissionGranted = false,
            ),
        )
    }

    @Test
    fun missingVpnGrantRequiresExplicitUserReconnect() {
        assertEquals(
            TunnelResumeAction.RESET_FOR_PERMISSION,
            TunnelResumePolicy.decide(ProxyVpnService.STATE_CONNECTING, vpnPermissionGranted = false),
        )
    }

    @Test
    fun deadServiceStartsFreshTunnel() {
        assertEquals(
            TunnelServiceReconcileAction.START_TUNNEL,
            TunnelServiceReconcilePolicy.decide(
                stopping = false,
                failoverHandoff = false,
                workerAlive = false,
                preflightAlive = false,
                tunPresent = false,
                hasActivePrepared = false,
            ),
        )
    }

    @Test
    fun healthyWorkerRepublishesConnectedInsteadOfRestarting() {
        assertEquals(
            TunnelServiceReconcileAction.REPORT_CONNECTED,
            TunnelServiceReconcilePolicy.decide(
                stopping = false,
                failoverHandoff = false,
                workerAlive = true,
                preflightAlive = false,
                tunPresent = true,
                hasActivePrepared = true,
            ),
        )
    }

    @Test
    fun liveStartupOrHandoffRepublishesConnecting() {
        assertEquals(
            TunnelServiceReconcileAction.REPORT_CONNECTING,
            TunnelServiceReconcilePolicy.decide(
                stopping = false,
                failoverHandoff = false,
                workerAlive = false,
                preflightAlive = true,
                tunPresent = false,
                hasActivePrepared = false,
            ),
        )
        assertEquals(
            TunnelServiceReconcileAction.REPORT_CONNECTING,
            TunnelServiceReconcilePolicy.decide(
                stopping = true,
                failoverHandoff = true,
                workerAlive = false,
                preflightAlive = false,
                tunPresent = false,
                hasActivePrepared = false,
            ),
        )
    }
}
