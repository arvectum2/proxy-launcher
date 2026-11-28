package ru.arvectum.apl.acceptance.client;

import android.app.Activity;
import android.content.Intent;
import android.net.*;
import android.os.Bundle;
import android.os.SystemClock;
import java.net.*;
import java.util.Arrays;

/** Separate UID; never opens a socket until the specific fixture VPN route is verified. */
public final class NativeClient extends Activity {
    public static final String OWNER="ru.arvectum.apl.acceptance";
    public static final String PERMISSION=OWNER+".FIXTURE";
    @Override public void onCreate(Bundle b) {
        super.onCreate(b);
        final boolean revoke=getIntent().getBooleanExtra("revoke",false);
        new Thread(() -> {
            String result="PASS";
            try {
                ConnectivityManager cm=getSystemService(ConnectivityManager.class);
                InetAddress address=InetAddress.getByName("192.0.2.17");
                long end=SystemClock.elapsedRealtime()+8000;
                Network vpn=null;
                while(SystemClock.elapsedRealtime()<end) {
                    Network n=cm.getActiveNetwork();
                    NetworkCapabilities caps=n==null?null:cm.getNetworkCapabilities(n);
                    LinkProperties lp=n==null?null:cm.getLinkProperties(n);
                    if(caps!=null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) && lp!=null &&
                        lp.getRoutes().stream().anyMatch(r -> r.getDestination().getPrefixLength()==32 &&
                            r.getDestination().getAddress().equals(address))) { vpn=n;break; }
                    Thread.sleep(100);
                }
                if(vpn==null) throw new IllegalStateException("No active fixture VPN");
                try(Socket socket=new Socket()) {
                    socket.setSoTimeout(8000);socket.connect(new InetSocketAddress(address,18080),8000);
                    socket.getOutputStream().write("APL-PROBE".getBytes("US-ASCII"));socket.getOutputStream().flush();
                    if(!Arrays.equals(socket.getInputStream().readNBytes(9),"APL-REPLY".getBytes("US-ASCII")))
                        throw new IllegalStateException("Reply mismatch");
                }
            } catch(Throwable t) { result="FAIL:"+t.getClass().getSimpleName()+":"+t.getMessage(); }
            Intent response=new Intent(OWNER+".CLIENT_RESULT").setPackage(OWNER)
                .putExtra("result",result).putExtra("uid",android.os.Process.myUid());
            sendBroadcast(response,PERMISSION);
            if(revoke && result.equals("PASS")) runOnUiThread(() -> {
                Intent consent=VpnService.prepare(this);
                if(consent!=null) startActivityForResult(consent,924);
            }); else runOnUiThread(this::finish);
        },"fixture-client").start();
    }
    public static final class ConsentService extends VpnService {}
}
