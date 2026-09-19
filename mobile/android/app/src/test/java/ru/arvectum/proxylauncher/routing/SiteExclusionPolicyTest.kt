package ru.arvectum.proxylauncher.routing

import java.net.InetAddress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SiteExclusionPolicyTest {
    @Test
    fun normalizesDesktopStyleInputs() {
        assertEquals(
            listOf("2001:db8::1", "example.com"),
            SiteExclusionPolicy.normalizeAll(
                listOf(
                    " https://Example.com/path?q=1 ",
                    "example.com:443",
                    "[2001:db8::1]:8443/path",
                    "EXAMPLE.COM",
                ),
            ),
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun wildcardIsRejectedInsteadOfSilentlyMisrouting() {
        SiteExclusionPolicy.normalizeAll(listOf("*.example.com"))
    }

    @Test
    fun oneIpv4ExclusionProducesExactComplement() {
        val excluded = InetAddress.getByName("203.0.113.7")
        val routes = SiteExclusionPolicy.complementRoutes(listOf(excluded), 4)
        assertEquals(32, routes.size)
        assertFalse(routes.any { contains(it, excluded) })
        assertTrue(routes.any { contains(it, InetAddress.getByName("203.0.113.6")) })
        assertTrue(routes.any { contains(it, InetAddress.getByName("8.8.8.8")) })
    }

    @Test
    fun multipleIpv4ExclusionsStayExcluded() {
        val excluded = listOf(
            InetAddress.getByName("10.0.0.1"),
            InetAddress.getByName("10.0.0.2"),
            InetAddress.getByName("192.0.2.50"),
        )
        val routes = SiteExclusionPolicy.complementRoutes(excluded, 4)
        excluded.forEach { address ->
            assertFalse(routes.any { contains(it, address) })
        }
        assertTrue(routes.any { contains(it, InetAddress.getByName("1.1.1.1")) })
    }

    @Test
    fun ipv6ExclusionProducesExactComplement() {
        val excluded = InetAddress.getByName("2001:db8::1234")
        val routes = SiteExclusionPolicy.complementRoutes(listOf(excluded), 16)
        assertEquals(128, routes.size)
        assertFalse(routes.any { contains(it, excluded) })
        assertTrue(routes.any { contains(it, InetAddress.getByName("2001:db8::1235")) })
    }

    private fun contains(route: IpRoute, address: InetAddress): Boolean {
        val routeBytes = route.address.address
        val addressBytes = address.address
        if (routeBytes.size != addressBytes.size) return false
        for (bit in 0 until route.prefixLength) {
            val byteIndex = bit / 8
            val mask = 1 shl (7 - bit % 8)
            if ((routeBytes[byteIndex].toInt() and mask) !=
                (addressBytes[byteIndex].toInt() and mask)
            ) return false
        }
        return true
    }
}
