package ru.arvectum.proxylauncher.tunnel

import java.io.BufferedInputStream
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import android.os.Looper
import android.os.NetworkOnMainThreadException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.Base64
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import ru.arvectum.proxylauncher.model.ProxyProfile
import ru.arvectum.proxylauncher.model.ProxyType

class ProxyProbeException(message: String) : Exception(message)

/**
 * Reuses one host/port/credential set. AUTO prefers the system-proxy-compatible
 * HTTP CONNECT path, then SOCKS5, and only then TLS-to-proxy HTTPS transport.
 */
class ProxyProtocolProbe {
    fun resolve(
        profile: ProxyProfile,
        password: String?,
        onCandidate: ((ProxyType) -> Unit)? = null,
        protectSocket: ((Socket) -> Boolean)? = null,
    ): ProxyProfile {
        check(Looper.myLooper() != Looper.getMainLooper()) {
            "Внутренняя ошибка: проверка прокси запущена в главном потоке"
        }

        val candidates = when (profile.type) {
            ProxyType.AUTO -> listOf(ProxyType.HTTP, ProxyType.SOCKS5, ProxyType.HTTPS)
            else -> listOf(profile.type)
        }
        val failures = mutableListOf<String>()

        for (candidate in candidates) {
            onCandidate?.invoke(candidate)
            try {
                when (candidate) {
                    ProxyType.HTTPS -> probeHttp(profile, password, tls = true, protectSocket = protectSocket)
                    ProxyType.HTTP -> probeHttp(profile, password, tls = false, protectSocket = protectSocket)
                    ProxyType.SOCKS5 -> probeSocks5(profile, password, protectSocket)
                    ProxyType.AUTO -> error("AUTO must be resolved before probing")
                }
                return profile.copy(type = candidate)
            } catch (e: ProxyProbeException) {
                failures += "${label(candidate)}: ${e.message}"
            } catch (e: Exception) {
                failures += "${label(candidate)}: ${friendlyNetworkError(e)}"
            }
        }

        val detail = failures.joinToString("; ").take(MAX_ERROR_LENGTH)
        throw ProxyProbeException(
            if (detail.isBlank()) "Прокси недоступен"
            else "Не удалось подобрать протокол. $detail",
        )
    }

    private fun probeHttp(
        profile: ProxyProfile,
        password: String?,
        tls: Boolean,
        protectSocket: ((Socket) -> Boolean)?,
    ) {
        val socket = if (tls) {
            openTlsSocket(profile.host, profile.port, protectSocket)
        } else {
            openTcpSocket(profile.host, profile.port, protectSocket)
        }
        socket.use { connection ->
            connection.soTimeout = IO_TIMEOUT_MS
            val writer = BufferedWriter(OutputStreamWriter(connection.getOutputStream(), Charsets.ISO_8859_1))
            val auth = profile.username?.let { user ->
                Base64.getEncoder().encodeToString("$user:${password.orEmpty()}".toByteArray(Charsets.UTF_8))
            }

            writer.write("CONNECT $PROBE_HOST:$PROBE_PORT HTTP/1.1\r\n")
            writer.write("Host: $PROBE_HOST:$PROBE_PORT\r\n")
            writer.write("Proxy-Connection: close\r\n")
            if (auth != null) writer.write("Proxy-Authorization: Basic $auth\r\n")
            writer.write("\r\n")
            writer.flush()

            val reader = BufferedReader(InputStreamReader(connection.getInputStream(), Charsets.ISO_8859_1))
            val statusLine = reader.readLine() ?: throw ProxyProbeException("нет ответа на CONNECT")
            if (!statusLine.startsWith("HTTP/")) throw ProxyProbeException("ответ не похож на HTTP proxy")

            val status = statusLine.split(' ').getOrNull(1)?.toIntOrNull()
                ?: throw ProxyProbeException("не удалось прочитать HTTP status")
            val authHeaders = mutableListOf<String>()
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isEmpty()) break
                if (line.startsWith("Proxy-Authenticate:", ignoreCase = true)) {
                    authHeaders += line.substringAfter(':').trim()
                }
            }

            when {
                status in 200..299 -> return
                status == 407 && profile.username.isNullOrBlank() ->
                    throw ProxyProbeException("прокси требует логин/пароль")
                status == 407 && authHeaders.any { it.startsWith("Digest", ignoreCase = true) } ->
                    return
                status == 407 -> throw ProxyProbeException("логин/пароль отклонены")
                else -> throw ProxyProbeException("CONNECT вернул HTTP $status")
            }
        }
    }

    private fun probeSocks5(
        profile: ProxyProfile,
        password: String?,
        protectSocket: ((Socket) -> Boolean)?,
    ) {
        openTcpSocket(profile.host, profile.port, protectSocket).use { socket ->
            socket.soTimeout = IO_TIMEOUT_MS
            val input = BufferedInputStream(socket.getInputStream())
            val output = socket.getOutputStream()

            val hasCredentials = !profile.username.isNullOrBlank()
            val methods = if (hasCredentials) byteArrayOf(0x00, 0x02) else byteArrayOf(0x00)
            output.write(byteArrayOf(0x05, methods.size.toByte()) + methods)
            output.flush()

            val greeting = readExactly(input, 2)
            if ((greeting[0].toInt() and 0xff) != 0x05) throw ProxyProbeException("не SOCKS5")
            when (greeting[1].toInt() and 0xff) {
                0x00 -> Unit
                0x02 -> authenticateSocks(input, output, profile.username, password)
                0xff -> throw ProxyProbeException("нет совместимого способа авторизации")
                else -> throw ProxyProbeException("неподдерживаемая SOCKS5-авторизация")
            }

            val domain = PROBE_HOST.toByteArray(Charsets.US_ASCII)
            val request = ByteArray(7 + domain.size)
            request[0] = 0x05
            request[1] = 0x01
            request[2] = 0x00
            request[3] = 0x03
            request[4] = domain.size.toByte()
            domain.copyInto(request, 5)
            request[5 + domain.size] = ((PROBE_PORT shr 8) and 0xff).toByte()
            request[6 + domain.size] = (PROBE_PORT and 0xff).toByte()
            output.write(request)
            output.flush()

            val reply = readExactly(input, 4)
            if ((reply[0].toInt() and 0xff) != 0x05) throw ProxyProbeException("некорректный SOCKS5-ответ")
            val result = reply[1].toInt() and 0xff
            if (result != 0x00) throw ProxyProbeException("CONNECT отклонён (код $result)")

            when (reply[3].toInt() and 0xff) {
                0x01 -> readExactly(input, 4)
                0x03 -> readExactly(input, readExactly(input, 1)[0].toInt() and 0xff)
                0x04 -> readExactly(input, 16)
                else -> throw ProxyProbeException("неизвестный тип SOCKS5-адреса")
            }
            readExactly(input, 2)
        }
    }

    private fun authenticateSocks(
        input: BufferedInputStream,
        output: java.io.OutputStream,
        username: String?,
        password: String?,
    ) {
        if (username.isNullOrBlank()) throw ProxyProbeException("прокси требует логин/пароль")
        val user = username.toByteArray(Charsets.UTF_8)
        val pass = password.orEmpty().toByteArray(Charsets.UTF_8)
        if (user.size !in 1..255 || pass.size > 255) throw ProxyProbeException("слишком длинный логин/пароль")

        val auth = ByteArray(3 + user.size + pass.size)
        auth[0] = 0x01
        auth[1] = user.size.toByte()
        user.copyInto(auth, 2)
        auth[2 + user.size] = pass.size.toByte()
        pass.copyInto(auth, 3 + user.size)
        output.write(auth)
        output.flush()

        val response = readExactly(input, 2)
        if ((response[1].toInt() and 0xff) != 0x00) throw ProxyProbeException("логин/пароль отклонены")
    }

    private fun openTcpSocket(
        host: String,
        port: Int,
        protectSocket: ((Socket) -> Boolean)?,
    ): Socket = Socket().apply {
        protectBeforeConnect(this, protectSocket)
        connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
        soTimeout = IO_TIMEOUT_MS
    }

    private fun openTlsSocket(
        host: String,
        port: Int,
        protectSocket: ((Socket) -> Boolean)?,
    ): SSLSocket {
        val socket = SSLSocketFactory.getDefault().createSocket() as SSLSocket
        protectBeforeConnect(socket, protectSocket)
        socket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
        socket.soTimeout = TLS_HANDSHAKE_TIMEOUT_MS
        socket.sslParameters = socket.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
        socket.startHandshake()
        socket.soTimeout = IO_TIMEOUT_MS
        return socket
    }

    private fun protectBeforeConnect(socket: Socket, protectSocket: ((Socket) -> Boolean)?) {
        if (protectSocket != null && !protectSocket(socket)) {
            socket.close()
            throw ProxyProbeException("не удалось исключить health-check из VPN-туннеля")
        }
    }

    private fun readExactly(input: BufferedInputStream, count: Int): ByteArray {
        val result = ByteArray(count)
        var offset = 0
        while (offset < count) {
            val read = input.read(result, offset, count - offset)
            if (read < 0) throw ProxyProbeException("соединение закрыто прокси")
            offset += read
        }
        return result
    }

    private fun label(type: ProxyType): String = when (type) {
        ProxyType.AUTO -> "Авто"
        ProxyType.HTTPS -> "HTTPS"
        ProxyType.HTTP -> "HTTP"
        ProxyType.SOCKS5 -> "SOCKS5"
    }

    private fun friendlyNetworkError(error: Exception): String =
        when (error) {
            is NetworkOnMainThreadException -> "внутренняя ошибка: сетевой тест в главном потоке"
            is java.net.SocketTimeoutException -> "таймаут"
            is javax.net.ssl.SSLException -> "TLS не поддерживается или сертификат не прошёл проверку"
            is java.net.ConnectException -> "соединение отклонено"
            is java.net.UnknownHostException -> "адрес не найден"
            else -> error.message?.take(80) ?: "ошибка соединения"
        }

    companion object {
        private const val PROBE_HOST = "example.com"
        private const val PROBE_PORT = 443
        private const val CONNECT_TIMEOUT_MS = 2500
        private const val TLS_HANDSHAKE_TIMEOUT_MS = 3000
        private const val IO_TIMEOUT_MS = 3000
        private const val MAX_ERROR_LENGTH = 420
    }
}
