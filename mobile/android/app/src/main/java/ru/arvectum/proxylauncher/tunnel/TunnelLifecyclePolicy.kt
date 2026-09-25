package ru.arvectum.proxylauncher.tunnel

enum class TunnelResumeAction {
    NONE,
    RECONCILE_SERVICE,
    RESET_FOR_PERMISSION,
}

object TunnelResumePolicy {
    fun requiresVpnPermissionCheck(state: String): Boolean =
        state == ProxyVpnService.STATE_CONNECTED ||
            state == ProxyVpnService.STATE_CONNECTING

    fun decide(state: String, vpnPermissionGranted: Boolean): TunnelResumeAction {
        if (!requiresVpnPermissionCheck(state)) return TunnelResumeAction.NONE
        return if (vpnPermissionGranted) {
            TunnelResumeAction.RECONCILE_SERVICE
        } else {
            TunnelResumeAction.RESET_FOR_PERMISSION
        }
    }
}

enum class TunnelServiceReconcileAction {
    START_TUNNEL,
    REPORT_CONNECTING,
    REPORT_CONNECTED,
}
object TunnelServiceReconcilePolicy {
    fun decide(
        stopping: Boolean,
        failoverHandoff: Boolean,
        workerAlive: Boolean,
        preflightAlive: Boolean,
        tunPresent: Boolean,
        hasActivePrepared: Boolean,
    ): TunnelServiceReconcileAction {
        if (stopping || failoverHandoff) {
            return TunnelServiceReconcileAction.REPORT_CONNECTING
        }
        if (workerAlive && hasActivePrepared) {
            return TunnelServiceReconcileAction.REPORT_CONNECTED
        }
        if (workerAlive || preflightAlive || tunPresent) {
            return TunnelServiceReconcileAction.REPORT_CONNECTING
        }
        return TunnelServiceReconcileAction.START_TUNNEL
    }
}
