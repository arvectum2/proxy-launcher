package com.github.shadowsocks.bg;

/**
 * Thin JNI compatibility bridge required by the upstream tun2proxy Android library.
 * The class/package name is part of tun2proxy's exported JNI ABI.
 */
public final class Tun2proxy {
    static {
        System.loadLibrary("tun2proxy");
    }

    public static native int run(String cliArgs, char tunMtu);
    public static native int stop();

    private Tun2proxy() {}
}
