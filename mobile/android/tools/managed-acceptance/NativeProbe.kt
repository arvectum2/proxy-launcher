package ru.arvectum.apl.acceptance

import android.app.*
import android.content.*
import android.net.*
import android.os.*
import android.view.accessibility.AccessibilityNodeInfo
import ru.arvectum.proxylauncher.MainActivity
import ru.arvectum.proxylauncher.model.*
import ru.arvectum.proxylauncher.tunnel.*
import java.net.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

/** Test-only VPN with one documentation address route, no default route or DNS. */
class NativeFixtureService:VpnService() {
    private val engine=Tun2ProxyEngineAdapter()
    private var tun:ParcelFileDescriptor?=null
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int {
        check(packageName=="ru.arvectum.apl.acceptance")
        check(intent?.action=="fixture.START")
        val port=intent!!.getIntExtra("port",0);check(port in 1024..65535)
        val manager=getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("native-fixture","Local VPN fixture",NotificationManager.IMPORTANCE_LOW))
        startForeground(923,Notification.Builder(this,"native-fixture").setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("Local VPN fixture").build())
        try {
            check(prepare(this)==null)
            tun=Builder().setSession("APL local fixture").setMtu(1500)
                .addAddress("10.99.0.2",32).addRoute("192.0.2.17",32)
                .addAllowedApplication(packageName).establish() ?: error("TUN unavailable")
            val fd=tun!!
            thread(name="native-fixture-engine",isDaemon=true) {
                try { engineResult.set(engine.run(fd,ProxyProfile("fixture","Fixture","127.0.0.1",port,ProxyType.HTTP),null,TunnelDnsMode.DIRECT)) }
                catch(t:Throwable) { engineError.set(t.javaClass.simpleName) }
                finally { exited.countDown() }
            }
        } catch(t:Throwable) { engineError.set(t.javaClass.simpleName);stopSelf() }
        finally { established.countDown() }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        try { stopResult.set(engine.stop()) } finally {
            runCatching { tun?.close() };tun=null
            stopForeground(STOP_FOREGROUND_REMOVE);destroyed.countDown();super.onDestroy()
        }
    }
    override fun onRevoke() { stopSelf() }
    companion object {
        val established=CountDownLatch(1);val exited=CountDownLatch(1);val destroyed=CountDownLatch(1)
        val engineResult=AtomicReference<Int?>();val stopResult=AtomicReference<Int?>();val engineError=AtomicReference<String?>()
    }
}

/** Normal Android consent dialog, disposable AVD only. */
class NativeProbe:Instrumentation() {
    override fun onCreate(arguments:Bundle?) { super.onCreate(arguments);start() }
    override fun onStart() {
        val report=Bundle();var stage="init";var activity:MainActivity?=null;var server:ServerSocket?=null
        var started=false;var failure:Throwable?=null
        val service=NativeFixtureService::class.java
        try {
            val c=targetContext;check(c.packageName=="ru.arvectum.apl.acceptance")
            stage="jni"
            Class.forName("com.github.shadowsocks.bg.Tun2proxy",true,c.classLoader)
            report.putString("native_jni_load","PASS")
            val a=startActivitySync(Intent(c,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            activity=a;waitForIdleSync()
            stage="consent"
            val permission=VpnService.prepare(a) ?: error("Fresh fixture must start without VPN consent")
            runOnMainSync { a.startActivityForResult(permission,923) }
            fun button(node:AccessibilityNodeInfo?):AccessibilityNodeInfo? {
                if(node==null) return null
                if(node.packageName?.toString()=="com.android.vpndialogs" && node.viewIdResourceName=="android:id/button1") return node
                for(i in 0 until node.childCount) button(node.getChild(i))?.let{return it}
                return null
            }
            val deadline=SystemClock.elapsedRealtime()+8000
            var clicked=false
            while(!clicked && SystemClock.elapsedRealtime()<deadline) {
                val node=button(uiAutomation.rootInActiveWindow)
                if(node!=null) clicked=node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                if(!clicked) Thread.sleep(100)
            }
            check(clicked) { "Expected Android VPN consent dialog not found" }
            val consentDeadline=SystemClock.elapsedRealtime()+8000
            while(VpnService.prepare(a)!=null && SystemClock.elapsedRealtime()<consentDeadline) Thread.sleep(100)
            check(VpnService.prepare(a)==null);report.putString("native_vpn_consent","PASS")
            stage="loopback_proxy"
            val local=ServerSocket(0,1,InetAddress.getByName("127.0.0.1"));server=local;local.soTimeout=12000
            val proxyError=AtomicReference<String?>();val proxyDone=CountDownLatch(1)
            thread(isDaemon=true,name="synthetic-loopback-proxy") {
                try { local.accept().use { socket ->
                    socket.soTimeout=8000;val input=socket.getInputStream().buffered();val output=socket.getOutputStream()
                    val headers=java.io.ByteArrayOutputStream();var end=false
                    while(headers.size()<4096) {
                        val byte=input.read();check(byte>=0);headers.write(byte)
                        if(headers.size()>=4 && headers.toString("US-ASCII").endsWith("\r\n\r\n")) { end=true;break }
                    }
                    check(end && headers.toString("US-ASCII").startsWith("CONNECT 192.0.2.17:18080 "))
                    output.write("HTTP/1.1 200 Connection Established\r\n\r\n".toByteArray());output.flush()
                    check(input.readNBytes(9).contentEquals("APL-PROBE".toByteArray()))
                    output.write("APL-REPLY".toByteArray());output.flush()
                } } catch(t:Throwable) { proxyError.set(t.javaClass.simpleName+":"+t.message?.take(80)) }
                finally { proxyDone.countDown() }
            }
            stage="tun"
            runOnMainSync { c.startForegroundService(Intent(c,service).setAction("fixture.START").putExtra("port",local.localPort)) };started=true
            check(NativeFixtureService.established.await(8,TimeUnit.SECONDS));check(NativeFixtureService.engineError.get()==null)
            val cm=c.getSystemService(ConnectivityManager::class.java);val route=InetAddress.getByName("192.0.2.17")
            fun vpnNetwork()=cm.allNetworks.singleOrNull { n ->
                cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN)==true &&
                    cm.getLinkProperties(n)?.routes?.any { it.destination.prefixLength==32 && it.destination.address==route }==true
            }
            val routeDeadline=SystemClock.elapsedRealtime()+8000
            while(vpnNetwork()==null && SystemClock.elapsedRealtime()<routeDeadline) Thread.sleep(100)
            val network=checkNotNull(vpnNetwork());report.putString("native_tun_route","PASS")
            stage="traffic"
            check(cm.activeNetwork==network) { "Fixture VPN is not the active network" }
            Socket().use { socket ->
                socket.soTimeout=8000;socket.connect(InetSocketAddress(route,18080),8000)
                socket.getOutputStream().write("APL-PROBE".toByteArray());socket.getOutputStream().flush()
                check(socket.getInputStream().readNBytes(9).contentEquals("APL-REPLY".toByteArray()))
            }
            check(proxyDone.await(3,TimeUnit.SECONDS));check(proxyError.get()==null){proxyError.get().orEmpty()}
            check(NativeFixtureService.engineError.get()==null);report.putString("native_loopback_roundtrip","PASS")
            stage="stop"
            runOnMainSync { c.stopService(Intent(c,service)) };started=false
            check(NativeFixtureService.destroyed.await(8,TimeUnit.SECONDS));check(NativeFixtureService.exited.await(8,TimeUnit.SECONDS))
            check(NativeFixtureService.engineError.get()==null);check(NativeFixtureService.stopResult.get()==0)
            report.putString("native_stop","PASS")
        } catch(t:Throwable) { failure=t }
        finally {
            if(started) runCatching { runOnMainSync { targetContext.stopService(Intent(targetContext,service)) } }
            runCatching { server?.close() };activity?.let { runCatching { runOnMainSync { it.finish() } } }
        }
        val error=failure;report.putString("result",if(error==null) "PASS" else "FAIL:$stage:${error.javaClass.simpleName}:${error.message?.take(120)}")
        finish(if(error==null) 0 else 1,report)
    }
}
