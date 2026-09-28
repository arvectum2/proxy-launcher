package ru.arvectum.proxylauncher.gateway

class FreeGatewayClient {
    fun listLocations(): List<FreeProxyLocation> = emptyList()

    fun createSession(locationId: String, displayName: String): FreeProxySession {
        throw IllegalStateException("Friends-only free gateway is not available in the public build")
    }

    companion object {
        val BOOTSTRAP_LOCATIONS: List<FreeProxyLocation> = emptyList()
    }
}
