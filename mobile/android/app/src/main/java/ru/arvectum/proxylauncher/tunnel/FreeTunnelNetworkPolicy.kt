package ru.arvectum.proxylauncher.tunnel

/**
 * Free gateway mode terminates tun2proxy at a local loopback HTTP proxy.
 * The Java TLS relay opens the real network socket for every CONNECT and the
 * APL package is already excluded from its own VPN. Recreating the whole VPN
 * on Android physical-network callbacks is therefore unnecessary and can
 * create a Wi-Fi/cellular handoff loop.
 */
object FreeTunnelNetworkPolicy {
    fun requiresPhysicalNetworkHandoff(isFreeSession: Boolean): Boolean = !isFreeSession
}
