package ru.arvectum.proxylauncher.gateway

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import ru.arvectum.proxylauncher.model.ProxyType

class FreeGatewayClientTest {
    @Test
    fun parsesPublicLocationsWithoutCredentials() {
        val locations = FreeGatewayJson.parseLocations(
            """{"locations":[{"id":"ru-free","label":"РФ","country_code":"RU"},{"id":"us-free","label":"США","country_code":"US"}]}""",
        )
        assertEquals(listOf("ru-free", "us-free"), locations.map { it.id })
        assertEquals(listOf("RU", "US"), locations.map { it.countryCode })
    }

    @Test
    fun buildsEphemeralHttpsProfileFromSession() {
        val session = FreeGatewayJson.parseSession(
            """{"proxy":{"host":"gateway.example","port":8443,"type":"HTTPS","username":"ru-free","password":"short-lived"},"expires_at":2000}""",
            "ru-free",
            "РФ · бесплатно",
        )
        assertEquals(ProxyType.HTTPS, session.profile.type)
        assertEquals("gateway.example", session.profile.host)
        assertEquals(8443, session.profile.port)
        assertEquals("ru-free", session.profile.username)
        assertEquals(null, session.profile.passwordRef)
        assertEquals("short-lived", session.password)
    }

    @Test
    fun schedulesRefreshBeforeExpiry() {
        val delay = FreeSessionRefreshPolicy.delayMillis(1_000, 4_600)
        assertEquals(3_300_000L, delay)
        assertTrue(FreeSessionRefreshPolicy.delayMillis(4_500, 4_600) >= 1_000L)
    }
}
