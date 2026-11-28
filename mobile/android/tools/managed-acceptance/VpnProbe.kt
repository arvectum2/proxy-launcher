package ru.arvectum.apl.acceptance

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.Instrumentation
import android.app.NotificationManager
import android.content.*
import android.os.*
import ru.arvectum.proxylauncher.MainActivity
import ru.arvectum.proxylauncher.storage.*
import ru.arvectum.proxylauncher.tunnel.ProxyVpnService
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Actual service and manifest lifecycle, no native engine or INTERNET permission. */
class VpnProbe:Instrumentation() {
    override fun onCreate(arguments:Bundle?) { super.onCreate(arguments);start() }
    override fun onStart() {
        val c=targetContext;val report=Bundle();var stage="init"
        var activity:MainActivity?=null
        val begun=System.currentTimeMillis()
        try {
            check(c.packageName=="ru.arvectum.apl.acceptance")
            check(c.checkSelfPermission(android.Manifest.permission.INTERNET)!=android.content.pm.PackageManager.PERMISSION_GRANTED)
            activity=startActivitySync(Intent(c,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            waitForIdleSync()
            val store=SecureProfileStore(c);check(store.listProfiles().isEmpty());store.setAutoProfileSelection(false)
            val gate=managedProfileGate(c)
            val disk=ManagedPreferenceDiskVerifier(c.dataDir.toPath().resolve("shared_prefs/apl_mobile_profiles_v1.xml"))
            val manager=c.getSystemService(ActivityManager::class.java)
            val notifications=c.getSystemService(NotificationManager::class.java)
            fun waitUntil(condition:()->Boolean) {
                val deadline=SystemClock.elapsedRealtime()+8000
                while(!condition() && SystemClock.elapsedRealtime()<deadline) Thread.sleep(50)
                check(condition()) { "bounded lifecycle timeout" }
            }
            fun noProcess()=manager.runningAppProcesses?.none { it.processName==c.packageName+":vpn" }==true
            fun launch(expected:String) {
                val terminal=CountDownLatch(1);var detail:String?=null
                val receiver=object:BroadcastReceiver(){
                    override fun onReceive(context:Context,intent:Intent) {
                        if(intent.getStringExtra(ProxyVpnService.EXTRA_STATE)==ProxyVpnService.STATE_ERROR){
                            detail=intent.getStringExtra(ProxyVpnService.EXTRA_DETAIL);terminal.countDown()
                        }
                    }
                }
                c.registerReceiver(receiver,IntentFilter(ProxyVpnService.ACTION_STATE),Context.RECEIVER_NOT_EXPORTED)
                try {
                    runOnMainSync { c.startForegroundService(Intent(c,ProxyVpnService::class.java).setAction(ProxyVpnService.ACTION_CONNECT)) }
                    check(terminal.await(8,TimeUnit.SECONDS)) { "no terminal broadcast" }
                    check(detail==expected) { "unexpected terminal detail" }
                    waitUntil { noProcess() && notifications.activeNotifications.none { it.id==1001 } }
                } finally { c.unregisterReceiver(receiver) }
            }
            stage="empty_pool"
            launch("Сначала добавьте прокси")
            gate.acquire().lease!!.use { check(it.isHeld()) }
            report.putString("vpn_empty_pool_stop","PASS")
            val baseline=disk.readVerified()
            stage="busy"
            gate.acquire().lease!!.use {
                launch("VPN unavailable: profile storage is not ready")
                check(it.isHeld());check(disk.matches(baseline))
            }
            report.putString("vpn_busy_denied","PASS")
            stage="pending"
            gate.acquire().lease!!.use { check(it.beginMutation()) }
            launch("VPN unavailable: profile storage is not ready")
            check(gate.acquire().status==ManagedCrashGate.Status.RECOVERY_REQUIRED)
            check(disk.matches(baseline));report.putString("vpn_pending_denied","PASS")
            stage="exit_reasons"
            if(Build.VERSION.SDK_INT>=30) {
                val exits=manager.getHistoricalProcessExitReasons(c.packageName,0,20).filter { it.timestamp>=begun && it.processName==c.packageName+":vpn" }
                check(exits.none { it.reason in setOf(ApplicationExitInfo.REASON_CRASH,ApplicationExitInfo.REASON_CRASH_NATIVE,ApplicationExitInfo.REASON_ANR) })
                report.putInt("vpn_exit_records",exits.size)
            }
            report.putString("result","PASS");finish(0,report)
        } catch(t:Throwable) { report.putString("result","FAIL:$stage:${t.javaClass.simpleName}:${t.message?.take(160)}");finish(1,report) }
        finally { activity?.let { runCatching { runOnMainSync { it.finish() } } } }
    }
}
