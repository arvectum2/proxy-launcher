package ru.arvectum.apl.acceptance

import android.app.Instrumentation
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.*
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import ru.arvectum.proxylauncher.storage.*
import java.security.KeyStore
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

private val before = mapOf<String,Any>("name" to "Synthetic <&> / тест", "port" to 80, "enabled" to true,
    "ids" to setOf("one","two"), "counter" to 7L, "ratio" to 1.25f)
private val after = before + ("port" to 81)
private const val ALIAS = "apl.disposable.acceptance.key"
private fun key(create:Boolean): SecretKey {
    val ks=KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (ks.getKey(ALIAS,null) as? SecretKey)?.let { return it }
    check(create)
    return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply {
        init(KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
    }.generateKey()
}
private fun prefs(c:Context)=c.getSharedPreferences("synthetic",Context.MODE_PRIVATE)
private fun disk(c:Context)=ManagedPreferenceDiskVerifier(c.dataDir.toPath().resolve("shared_prefs/synthetic.xml"))
private fun await(latch:CountDownLatch) { check(latch.await(8,TimeUnit.SECONDS)) { "bounded IPC timeout" } }

class Worker:Service() {
    private var crashLease:ManagedCrashGate.Lease?=null
    private val messenger=Messenger(Handler(Looper.getMainLooper()){msg ->
        when(msg.what) {
            1 -> {
                val status=ManagedVpnProcessLease.enter(managedProfileGate(this))
                msg.replyTo.send(Message.obtain(null,1,status.ordinal,Process.myPid()))
            }
            2 -> Process.killProcess(Process.myPid())
            3,4 -> {
                val a=managedProfileGate(this).acquire()
                crashLease=a.lease
                check(crashLease!!.beginMutation(ManagedRecoveryEvidence.create(before,after).seal(key(false))))
                if (msg.what==4) check(prefs(this).edit().putInt("port",81).commit())
                msg.replyTo.send(Message.obtain(null,msg.what,a.status.ordinal,Process.myPid()))
            }
        }
        true
    })
    override fun onBind(intent:Intent):IBinder=messenger.binder
    override fun onDestroy() { noBackupFilesDir.resolve("worker-destroyed").writeText("destroyed");super.onDestroy() }
}

class Probe:Instrumentation() {
    private var phase:String?=null
    override fun onCreate(arguments:Bundle?) { super.onCreate(arguments);phase=arguments?.getString("phase");start() }
    override fun onStart() {
        val c=targetContext
        val report=Bundle();var stage="init"
        val thread=HandlerThread("acceptance-ipc").apply { start() }
        var conn:ServiceConnection?=null
        try {
            check(c.packageName=="ru.arvectum.apl.acceptance")
            val gate=managedProfileGate(c)
            if (phase=="after") {
                stage="fresh_after"
                check(gate.acquire().status==ManagedCrashGate.Status.RECOVERY_REQUIRED)
                val durable={ disk(c).readVerified().also { check(prefs(c).all==it) } }
                val review=ManagedRecoveryReview.prepare(gate,{key(false)},durable,SystemClock::elapsedRealtime){true}!!
                check(review.state==ManagedRecoveryEvidence.State.AFTER)
                check(review.confirm(gate,{key(false)},durable){true})
                report.putString("fresh_after_recovery","PASS")
                stage="mixed"
                gate.acquire().lease!!.use { check(it.beginMutation(ManagedRecoveryEvidence.create(before,after).seal(key(false)))) }
                check(prefs(c).edit().putInt("port",82).commit())
                check(ManagedRecoveryReview.prepare(gate,{key(false)},durable,SystemClock::elapsedRealtime){true}==null)
                check(gate.acquire().status==ManagedCrashGate.Status.RECOVERY_REQUIRED)
                check(!gate.ordinaryWritesAllowed())
                report.putString("mixed_fail_closed","PASS");report.putString("result","PASS");finish(0,report);return
            }
            stage="xml"
            check(prefs(c).edit().putString("name",before["name"] as String).putInt("port",80)
                .putBoolean("enabled",true).putStringSet("ids",setOf("one","two")).putLong("counter",7L).putFloat("ratio",1.25f).commit())
            check(disk(c).matches(before));report.putString("xml_fsync","PASS")
            stage="keystore"
            val sealed=ManagedRecoveryEvidence.create(before,after).seal(key(true))
            check(ManagedRecoveryEvidence.open(sealed,key(false)).classify(disk(c).readVerified())==ManagedRecoveryEvidence.State.BEFORE)
            check(runCatching { ManagedRecoveryEvidence.open(sealed.copyOf().apply { this[20]=(this[20].toInt() xor 1).toByte() },key(false)) }.isFailure)
            report.putString("keystore","PASS")
            fun bind():IBinder {
                val ready=CountDownLatch(1);var binder:IBinder?=null
                val connection=object:ServiceConnection {
                    override fun onServiceConnected(n:ComponentName,b:IBinder) { binder=b;ready.countDown() }
                    override fun onServiceDisconnected(n:ComponentName) {}
                }
                check(c.bindService(Intent(c,Worker::class.java),connection,Context.BIND_AUTO_CREATE));conn=connection;await(ready)
                return checkNotNull(binder)
            }
            fun request(b:IBinder,op:Int):Pair<Int,Int> {
                val done=CountDownLatch(1);var result=0 to 0
                val reply=Messenger(Handler(thread.looper){m -> result=m.arg1 to m.arg2;done.countDown();true})
                Messenger(b).send(Message.obtain(null,op).apply { replyTo=reply });await(done);return result
            }
            fun unbind() { conn?.let { c.unbindService(it) };conn=null }
            fun kill(b:IBinder) { val dead=CountDownLatch(1);b.linkToDeath({dead.countDown()},0);Messenger(b).send(Message.obtain(null,2));await(dead);unbind() }
            stage="lease"
            var b=bind();val first=request(b,1);check(first.first==ManagedCrashGate.Status.ACQUIRED.ordinal)
            check(gate.acquire().status==ManagedCrashGate.Status.BUSY)
            val destroyed=c.noBackupFilesDir.resolve("worker-destroyed");destroyed.delete()
            unbind();val until=SystemClock.elapsedRealtime()+5000
            while (!destroyed.exists() && SystemClock.elapsedRealtime()<until) Thread.sleep(25)
            check(destroyed.exists());check(gate.acquire().status==ManagedCrashGate.Status.BUSY)
            b=bind();val second=request(b,1);check(second==first)
            check(gate.acquire().status==ManagedCrashGate.Status.BUSY);kill(b)
            gate.acquire().lease!!.use { check(it.isHeld()) };report.putString("process_lease","PASS")
            stage="crash"
            b=bind();check(request(b,3).first==ManagedCrashGate.Status.ACQUIRED.ordinal);kill(b)
            check(gate.acquire().status==ManagedCrashGate.Status.RECOVERY_REQUIRED)
            check(!gate.ordinaryWritesAllowed())
            val review=ManagedRecoveryReview.prepare(gate,{key(false)},{disk(c).readVerified()},SystemClock::elapsedRealtime){true}!!
            check(review.state==ManagedRecoveryEvidence.State.BEFORE)
            check(review.confirm(gate,{key(false)},{disk(c).readVerified()}){true})
            check(!review.confirm(gate,{key(false)},{disk(c).readVerified()}){true})
            gate.acquire().lease!!.use { check(it.isHeld()) };report.putString("crash_recovery","PASS")
            stage="cache"
            check(prefs(c).all["port"]==80)
            b=bind();check(request(b,4).first==ManagedCrashGate.Status.ACQUIRED.ordinal);kill(b)
            check(disk(c).matches(after));check(!disk(c).matches(before));report.putString("durable_change","PASS")
            check(prefs(c).all==before)
            val verified={ disk(c).readVerified().also { check(prefs(c).all==it) } }
            check(ManagedRecoveryReview.prepare(gate,{key(false)},verified,SystemClock::elapsedRealtime){true}==null)
            check(gate.acquire().status==ManagedCrashGate.Status.RECOVERY_REQUIRED)
            report.putString("stale_cache_blocked","PASS")
            report.putString("result","PASS");finish(0,report)
        } catch(t:Throwable) {
            report.putString("result","FAIL:$stage:${t.javaClass.simpleName}:${t.message?.take(160)}");finish(1,report)
        } finally { conn?.let { runCatching { c.unbindService(it) } };thread.quitSafely() }
    }
}
