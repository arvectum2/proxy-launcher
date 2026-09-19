import Darwin
import Foundation
import NetworkExtension
import tun2proxy

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private struct PreparedProxy {
        let storedProfile: ProxyProfile
        let resolvedProfile: ProxyProfile
        let password: String?
        let automaticSelection: Bool
        let latencyMs: Int
    }

    private let engineQueue = DispatchQueue(label: "ru.arvectum.proxylauncher.ios.tun2proxy")
    private let policy = FailoverPolicy()
    private let probe = ProxyProbe()
    private let telemetry = TelemetryStore()
    private var store: ProfileStore?
    private var tlsRelay: TLSProxyRelay?
    private var monitorTask: Task<Void, Never>?
    private var active: PreparedProxy?
    private var consecutiveFailures = 0
    private var switching = false
    private var stopping = false

    override func startTunnel(
        options: [String : NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        stopping = false
        do {
            store = try ProfileStore()
        } catch {
            completionHandler(error)
            return
        }

        Task {
            do {
                let prepared = try await selectProxy()
                try await apply(prepared)
                active = prepared
                telemetry.append(TunnelEvent(
                    type: "connected",
                    profileName: prepared.storedProfile.name,
                    detail: "\(prepared.resolvedProfile.type.label) · \(prepared.storedProfile.host):\(prepared.storedProfile.port)"
                ))
                if prepared.automaticSelection { startMonitor() }
                completionHandler(nil)
            } catch {
                telemetry.append(TunnelEvent(type: "error", detail: error.localizedDescription))
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        stopping = true
        monitorTask?.cancel()
        monitorTask = nil
        _ = tun2proxy_stop()
        tlsRelay?.stop()
        tlsRelay = nil
        if let active {
            telemetry.append(TunnelEvent(type: "disconnected", profileName: active.storedProfile.name))
        }
        active = nil
        completionHandler()
    }

    private func selectProxy() async throws -> PreparedProxy {
        guard let store else { throw tunnelError("Общее хранилище недоступно") }
        let profiles = store.listProfiles()
        guard !profiles.isEmpty else { throw tunnelError("Нет сохранённых прокси") }

        if !store.automaticSelection {
            guard let id = store.selectedProfileID,
                  let profile = profiles.first(where: { $0.id == id }) else {
                throw tunnelError("Выбранный прокси не найден")
            }
            return try await prepare(profile, automatic: false)
        }

        let now = Date()
        let failedID = policy.recentlyFailedStillSuppressed(now: now, failedAt: store.recentlyFailedAt)
            ? store.recentlyFailedProfileID
            : nil
        let orderedIDs = policy.orderCandidates(
            profileIDs: profiles.map(\.id),
            primaryID: store.primaryProfileID,
            lastSuccessfulID: store.lastAutoProfileID,
            recentlyFailedID: failedID
        )
        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        var failures: [String] = []
        for id in orderedIDs {
            guard let profile = byID[id] else { continue }
            do {
                let prepared = try await prepare(profile, automatic: true)
                store.lastAutoProfileID = profile.id
                return prepared
            } catch {
                failures.append("\(profile.name): \(error.localizedDescription)")
            }
        }
        throw tunnelError("Нет доступных прокси. " + failures.joined(separator: "; "))
    }

    private func prepare(_ profile: ProxyProfile, automatic: Bool) async throws -> PreparedProxy {
        guard let store else { throw tunnelError("Общее хранилище недоступно") }
        let password = try store.password(for: profile.id)
        let measured = try await probe.resolveMeasured(profile, password: password)
        return PreparedProxy(
            storedProfile: profile,
            resolvedProfile: measured.profile,
            password: password,
            automaticSelection: automatic,
            latencyMs: measured.latencyMs
        )
    }

    private func apply(_ prepared: PreparedProxy) async throws {
        tlsRelay?.stop()
        tlsRelay = nil

        var effective = prepared.resolvedProfile
        if effective.type == .https {
            let relay = TLSProxyRelay(host: effective.host, port: effective.port)
            let localPort = try await relay.start()
            tlsRelay = relay
            effective.host = "127.0.0.1"
            effective.port = localPort
            effective.type = .http
        }

        let exclusions = try resolveExclusions(for: prepared)
        let settings = networkSettings(excludedAddresses: exclusions)
        try await setSettings(settings)

        guard let tunFD = tunnelFileDescriptor(forAddress: "192.0.2.1"), tunFD >= 0 else {
            throw tunnelError("Не удалось получить файловый дескриптор Packet Tunnel")
        }

        let proxyURL = try buildProxyURL(profile: effective, password: prepared.password)
        let args = "tun2proxy-bin --proxy \(proxyURL) --tun-fd \(tunFD) --close-fd-on-drop false --dns over-tcp --ipv6-enabled --verbosity warn"
        engineQueue.async { [weak self] in
            let result = args.withCString {
                tun2proxy_run_with_cli_args($0, 1500, true)
            }
            guard let self, !self.stopping else { return }
            if result != 0 {
                self.telemetry.append(TunnelEvent(
                    type: "engine stopped",
                    profileName: prepared.storedProfile.name,
                    detail: "tun2proxy code \(result)"
                ))
            }
        }
        try await Task.sleep(nanoseconds: 350_000_000)
    }

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !self.stopping {
                try? await Task.sleep(nanoseconds: UInt64(self.policy.tuning.healthInterval * 1_000_000_000))
                if Task.isCancelled || self.stopping { break }
                await self.monitorIteration()
            }
        }
    }

    private func monitorIteration() async {
        guard !switching, let current = active, current.automaticSelection, let store else { return }

        if store.restorePolicy == .returnToPrimary,
           let primaryID = store.primaryProfileID,
           primaryID != current.storedProfile.id,
           policy.cooldownElapsed(now: Date(), lastSwitch: store.lastFailoverAt),
           let primary = store.profile(id: primaryID),
           let prepared = try? await prepare(primary, automatic: true) {
            await switchTo(prepared, reason: "primary restored")
            return
        }

        do {
            _ = try await probe.resolveMeasured(current.resolvedProfile, password: current.password)
            consecutiveFailures = 0
        } catch {
            consecutiveFailures += 1
            guard policy.failureConfirmed(consecutiveFailures) else { return }
            store.markRecentlyFailed(current.storedProfile.id)
            store.lastFailoverAt = Date()
            telemetry.append(TunnelEvent(
                type: "proxy unavailable",
                profileName: current.storedProfile.name,
                detail: error.localizedDescription
            ))
            do {
                let next = try await selectProxy()
                await switchTo(next, reason: "failover")
            } catch {
                telemetry.append(TunnelEvent(type: "failover failed", detail: error.localizedDescription))
            }
        }
    }

    private func switchTo(_ prepared: PreparedProxy, reason: String) async {
        guard !switching, !stopping else { return }
        switching = true
        defer { switching = false }
        _ = tun2proxy_stop()
        tlsRelay?.stop()
        tlsRelay = nil
        try? await Task.sleep(nanoseconds: 300_000_000)
        do {
            try await apply(prepared)
            active = prepared
            consecutiveFailures = 0
            store?.lastAutoProfileID = prepared.storedProfile.id
            store?.lastFailoverAt = Date()
            if reason == "primary restored" { store?.clearRecentlyFailed() }
            telemetry.append(TunnelEvent(
                type: reason,
                profileName: prepared.storedProfile.name,
                detail: prepared.resolvedProfile.type.label
            ))
        } catch {
            telemetry.append(TunnelEvent(type: "switch failed", detail: error.localizedDescription))
        }
    }

    private func resolveExclusions(for prepared: PreparedProxy) throws -> [String] {
        guard let store else { return [] }
        var addresses = Set<String>()
        for entry in store.siteExclusions {
            for address in try resolveHost(entry) { addresses.insert(address) }
        }
        for address in try resolveHost(prepared.storedProfile.host) { addresses.insert(address) }
        if addresses.count > SiteExclusionPolicy.maxResolvedAddresses {
            throw tunnelError("Слишком много IP-адресов в исключениях")
        }
        return addresses.sorted()
    }

    private func networkSettings(excludedAddresses: [String]) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "192.0.2.2")
        settings.mtu = 1500

        let ipv4 = NEIPv4Settings(addresses: ["192.0.2.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = excludedAddresses
            .filter { $0.contains(".") }
            .map { NEIPv4Route(destinationAddress: $0, subnetMask: "255.255.255.255") }
        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(addresses: ["2001:db8::1"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [
            NEIPv6Route(destinationAddress: "::", networkPrefixLength: 1),
            NEIPv6Route(destinationAddress: "8000::", networkPrefixLength: 1),
        ]
        ipv6.excludedRoutes = excludedAddresses
            .filter { $0.contains(":") }
            .map { NEIPv6Route(destinationAddress: $0, networkPrefixLength: 128) }
        settings.ipv6Settings = ipv6
        return settings
    }

    private func setSettings(_ settings: NEPacketTunnelNetworkSettings) async throws {
        try await withCheckedThrowingContinuation { continuation in
            setTunnelNetworkSettings(settings) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func buildProxyURL(profile: ProxyProfile, password: String?) throws -> String {
        var components = URLComponents()
        switch profile.type {
        case .http: components.scheme = "http"
        case .socks5: components.scheme = "socks5"
        case .https, .auto: throw tunnelError("Прокси-протокол не разрешён перед запуском движка")
        }
        components.host = profile.host
        components.port = profile.port
        if let username = profile.username, !username.isEmpty {
            components.user = username
            if let password { components.password = password }
        }
        guard let value = components.url?.absoluteString else {
            throw tunnelError("Не удалось сформировать URL прокси")
        }
        return value
    }

    private func resolveHost(_ host: String) throws -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: Int32(SOCK_STREAM.rawValue),
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0, let first = result else {
            throw tunnelError("Не удалось разрешить исключение: \(host)")
        }
        defer { freeaddrinfo(first) }

        var addresses = Set<String>()
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor?.pointee {
            if let address = info.ai_addr {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    address,
                    info.ai_addrlen,
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    addresses.insert(String(cString: buffer).components(separatedBy: "%").first ?? "")
                }
            }
            cursor = info.ai_next
        }
        return addresses.filter { !$0.isEmpty }.sorted()
    }

    private func tunnelFileDescriptor(forAddress address: String) -> Int32? {
        let targetName = interfaceName(forAddress: address)
        for fd in Int32(0)...Int32(1024) {
            var buffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
            var length = socklen_t(buffer.count)
            let result = buffer.withUnsafeMutableBytes { bytes in
                getsockopt(fd, 2, 2, bytes.baseAddress, &length)
            }
            if result == 0 {
                let name = String(cString: buffer)
                if let targetName {
                    if name == targetName { return fd }
                } else if name.hasPrefix("utun") {
                    return fd
                }
            }
        }
        return nil
    }

    private func interfaceName(forAddress target: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            guard let address = entry.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = family == AF_INET
                ? socklen_t(MemoryLayout<sockaddr_in>.size)
                : socklen_t(MemoryLayout<sockaddr_in6>.size)
            if getnameinfo(address, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: buffer).components(separatedBy: "%").first ?? ""
                if value == target { return String(cString: entry.ifa_name) }
            }
        }
        return nil
    }

    private func tunnelError(_ message: String) -> Error {
        NSError(domain: "ru.arvectum.proxylauncher.ios.tunnel", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}
