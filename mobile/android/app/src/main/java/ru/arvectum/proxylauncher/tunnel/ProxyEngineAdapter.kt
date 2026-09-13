package ru.arvectum.proxylauncher.tunnel

import android.os.ParcelFileDescriptor
import ru.arvectum.proxylauncher.model.ProxyProfile

/** Engine boundary. UI and profile storage must not depend on sing-box or any other engine. */
interface ProxyEngineAdapter {
    suspend fun start(tun: ParcelFileDescriptor, profile: ProxyProfile)
    suspend fun stop()
}

/** Safe spike implementation: refuses to claim a working tunnel until an engine is wired. */
class UnwiredProxyEngineAdapter : ProxyEngineAdapter {
    override suspend fun start(tun: ParcelFileDescriptor, profile: ProxyProfile) {
        tun.close()
        error("Proxy engine is not wired yet")
    }

    override suspend fun stop() = Unit
}
