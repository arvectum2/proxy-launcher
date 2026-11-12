import Darwin
import Foundation
import NetworkExtension
import XCTest
@testable import Arvectum_Proxy_Launcher

/// Explicitly opt-in physical hardware QA. The real signed app hosts this
/// test, but the tunnel has independent host (20s) and extension (25s) stop
/// guards. No user profiles, secrets, preferences or IDs are logged.
final class PhysicalVPNEgressHostTests: XCTestCase {
#if APL_RUN_EXPLICIT_VPN_QA
    private struct Egress: Equatable {
        let ipify: String
        let cloudflare: String
    }
    private enum ReceiptError: Error { case invalid }

    private func egress() async throws -> Egress {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        config.urlCache = nil
        let client = URLSession(configuration: config)
        defer { client.invalidateAndCancel() }

        @Sendable func fetch(_ address: String) async throws -> String {
            guard let url = URL(string: address) else { throw ReceiptError.invalid }
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 4
            let (bytes, response) = try await client.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  bytes.count < 4096, let string = String(data: bytes, encoding: .utf8)
            else { throw ReceiptError.invalid }
            return string
        }
        async let first = fetch("https://api.ipify.org")
        async let second = fetch("https://www.cloudflare.com/cdn-cgi/trace")
        let firstResult = try await first
        let secondResult = try await second
        let ip = firstResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let traceIP = secondResult.split(separator: "\n")
            .first(where: { $0.hasPrefix("ip=") })
            .map { String($0.dropFirst(3)) } ?? ""
        guard (3..<48).contains(ip.count), (3..<48).contains(traceIP.count),
              !ip.contains(" "), !traceIP.contains(" ")
        else { throw ReceiptError.invalid }
        return Egress(ipify: ip, cloudflare: traceIP)
    }

    private func existingOffTunnel() async throws -> NETunnelProviderSession {
        let managers: [NETunnelProviderManager] = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { list, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: list ?? []) }
            }
        }
        let ourManagers = managers.filter {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == "ru.arvectum.proxylauncher.ios.PacketTunnel"
        }
        guard let manager = ourManagers.first(where: { $0.isEnabled }),
              manager.connection.status == .disconnected,
              let session = manager.connection as? NETunnelProviderSession
        else { throw XCTSkip("APL VPN must be installed, enabled and already OFF") }
        return session
    }

    // IPv4-only and IPv6-only endpoints are used to distinguish native
    // dual-stack PacketTunnel egress from a generic HTTPS success.
    private struct DualStack: Equatable {
        let ipv4: String
        let ipv6: String
    }

    private func ipFamilyReceipt(_ urlString: String, family: Int32) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 7
        let client = URLSession(configuration: config)
        defer { client.invalidateAndCancel() }

        guard let url = URL(string: urlString) else { throw ReceiptError.invalid }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (body, response) = try await client.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              body.count < 128, let raw = String(data: body, encoding: .utf8)
        else { throw ReceiptError.invalid }

        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var storage = in6_addr()
        guard address.withCString({ inet_pton(family, $0, &storage) == 1 }) else {
            throw ReceiptError.invalid
        }
        // This raw address is retained solely for in-process equality.
        // Do not log or persist it, along with owner proxy credentials.
        return address
    }

    // Two literal Cloudflare IP HTTPS endpoints allow distinguishing a broken
    // packet route from DNS/VirtualDNS resolution failures. The TLS cert is
    // still validated by URLSession; no trust bypass is enabled.
    private func literalFamilyReceipt(_ urlString: String, family: Int32) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 7
        let client = URLSession(configuration: config)
        defer { client.invalidateAndCancel() }
        guard let url = URL(string: urlString) else { throw ReceiptError.invalid }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (body, response) = try await client.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              body.count < 4096,
              let raw = String(data: body, encoding: .utf8),
              let ipLine = raw.split(separator: "\n").first(where: { $0.hasPrefix("ip=") })
        else { throw ReceiptError.invalid }
        let origin = String(ipLine.dropFirst(3))
        var storage = in6_addr()
        guard origin.withCString({ inet_pton(family, $0, &storage) == 1 }) else {
            throw ReceiptError.invalid
        }
        return origin // In-process only; never log raw public origins.
    }

    private func literalDualStack() async throws -> DualStack {
        async let v4 = literalFamilyReceipt("https://1.1.1.1/cdn-cgi/trace", family: AF_INET)
        async let v6 = literalFamilyReceipt("https://[2606:4700:4700::1111]/cdn-cgi/trace", family: AF_INET6)
        return try await DualStack(ipv4: v4, ipv6: v6)
    }

    private func dualStack() async throws -> DualStack {
        async let v4 = ipFamilyReceipt("https://ipv4.icanhazip.com", family: AF_INET)
        async let v6 = ipFamilyReceipt("https://api6.ipify.org", family: AF_INET6)
        return try await DualStack(ipv4: v4, ipv6: v6)
    }

    func testBoundedAPLPacketTunnelChangesAndRestoresPublicEgress() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Real PacketTunnel test requires specifically authorized iPhone")
#else
        let session = try await existingOffTunnel()
        let before: Egress
        do {
            before = try await egress()
            let check = try await egress()
            guard before == check else {
                throw XCTSkip("Public IP baseline volatile, no VPN activation")
            }
        } catch {
            throw XCTSkip("Public IP witness unavailable while VPN OFF")
        }
        print("APL_VPN_030_PREFLIGHT_OFF_STABLE_TWO_ORIGIN_SERVICES")

        // Guard #1: host timer calls stop at 20s. Guard #2: the PacketTunnel
        // itself cancels after 25s even if the host process is killed.
        var attempted = false
        var stopItem: DispatchWorkItem?
        defer {
            stopItem?.cancel()
            if attempted { session.stopVPNTunnel() }
        }
        attempted = true
        do {
            try session.startTunnel(options: [
                "requestedByUser": NSNumber(value: true),
                "qaStopAfterSeconds": NSNumber(value: 25)
            ])
        } catch {
            XCTFail("System VPN start refused; no private error details logged")
            return
        }
        let safety = DispatchWorkItem { session.stopVPNTunnel() }
        stopItem = safety
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 20, execute: safety
        )

        var connected = false
        // startTunnel(options:) is asynchronous; the first status sample may
        // still be .disconnected before the NE session enters .connecting.
        // Never misclassify that initial transition as an immediate failure.
        for attempt in 0..<48 {
            let state = session.status
            if state == .connected { connected = true; break }
            if state == .invalid || (state == .disconnected && attempt >= 16) {
                break
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard connected else {
            XCTFail("PacketTunnel did not connect; bounded auto-stop armed")
            return
        }
        print("APL_VPN_030_CONNECTED_WITH_20S_AND_25S_STOP_GUARDS")

        let during: Egress
        do { during = try await egress() }
        catch {
            XCTFail("HTTPS witnesses unavailable while real VPN was connected")
            return
        }
        let changed = (during.ipify != before.ipify ? 1 : 0)
            + (during.cloudflare != before.cloudflare ? 1 : 0)
        print("APL_VPN_030_ORIGIN_PROVIDERS_CHANGED_\(changed)_OF_2")

        stopItem?.cancel()
        session.stopVPNTunnel()
        var off = false
        for _ in 0..<40 {
            if session.status == .disconnected { off = true; break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        guard off else {
            XCTFail("VPN not OFF within 8s; extension kill timer armed")
            return
        }
        print("APL_VPN_030_EXPLICIT_OFF_CONFIRMED")

        var restored = 0
        for attempt in 1...3 {
            do {
                let after = try await egress()
                restored = (after.ipify == before.ipify ? 1 : 0)
                    + (after.cloudflare == before.cloudflare ? 1 : 0)
                if restored == 2 { break }
            } catch {}
            if attempt < 3 { try await Task.sleep(nanoseconds: 850_000_000) }
        }
        print("APL_VPN_030_ORIGIN_PROVIDERS_RESTORED_\(restored)_OF_2")
        XCTAssertEqual(changed, 2, "System VPN must change both public IP witnesses")
        XCTAssertEqual(restored, 2, "VPN OFF must restore both direct IP witnesses")
#endif
    }

    /// Opt-in real PacketTunnel IPv4+IPv6 QA; only with an existing OFF VPN.
    func testBoundedAPLPacketTunnelIPv4AndIPv6EgressAndRestore() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Real iPhone with existing proxy and PacketTunnel required")
#else
        let session = try await existingOffTunnel()
        let before: DualStack
        do {
            before = try await dualStack()
            let secondBaseline = try await dualStack()
            guard before == secondBaseline else {
                throw XCTSkip("Direct IPv4/IPv6 baseline volatile; VPN never enabled")
            }
        } catch {
            throw XCTSkip("Direct IPv4+IPv6 witness unavailable; VPN never enabled")
        }
        print("APL_VPN_DUALSTACK_BASELINE_IPV4_IPV6_STABLE_OFF")

        // Short-lived user-approved physical test only, Debug flag required.
        // App-host watchdog at 20 s, independent extension timeout at 25 s.
        var attempted = false
        var watchdog: DispatchWorkItem?
        defer {
            watchdog?.cancel()
            if attempted { session.stopVPNTunnel() }
        }
        attempted = true
        do {
            try session.startTunnel(options: [
                "requestedByUser": NSNumber(value: true),
                "qaStopAfterSeconds": NSNumber(value: 25)
            ])
        } catch {
            XCTFail("Bounded VPN start declined")
            return
        }
        let stop = DispatchWorkItem { session.stopVPNTunnel() }
        watchdog = stop
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 20, execute: stop
        )

        var connected = false
        for attempt in 0..<48 {
            let state = session.status
            if state == .connected { connected = true; break }
            if state == .invalid || (state == .disconnected && attempt >= 16) {
                break
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard connected else {
            XCTFail("Existing PacketTunnel did not enter connected state")
            return
        }
        print("APL_VPN_DUALSTACK_CONNECTED_GUARDS_20_25_SEC")

        var changedIPv4 = false
        var changedIPv6 = false
        var ipv4Receipt = false
        var ipv6Receipt = false
        do {
            let address = try await ipFamilyReceipt("https://ipv4.icanhazip.com", family: AF_INET)
            ipv4Receipt = true
            changedIPv4 = address != before.ipv4
            print("APL_VPN_DUALSTACK_IPV4_RECEIPT_OK_CHANGED_\(changedIPv4)")
        } catch {
            // A numeric URL error code is safe for diagnosis; raw errors can
            // embed user identifiers and must never be printed.
            print("APL_VPN_DUALSTACK_IPV4_RECEIPT_FAILED_CODE_\((error as NSError).code)")
        }
        do {
            let address = try await ipFamilyReceipt("https://api6.ipify.org", family: AF_INET6)
            ipv6Receipt = true
            changedIPv6 = address != before.ipv6
            print("APL_VPN_DUALSTACK_IPV6_RECEIPT_OK_CHANGED_\(changedIPv6)")
        } catch {
            print("APL_VPN_DUALSTACK_IPV6_RECEIPT_FAILED_CODE_\((error as NSError).code)")
        }
        print("APL_VPN_DUALSTACK_ON_IPV4_CHANGED_\(changedIPv4)_IPV6_CHANGED_\(changedIPv6)")

        watchdog?.cancel()
        session.stopVPNTunnel()
        var off = false
        for _ in 0..<40 {
            if session.status == .disconnected { off = true; break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        guard off else {
            XCTFail("PacketTunnel failed to restore OFF; extension timeout remains armed")
            return
        }
        print("APL_VPN_DUALSTACK_EXPLICIT_OFF_CONFIRMED")

        var restoredIPv4 = false
        var restoredIPv6 = false
        for attempt in 1...3 {
            do {
                let after = try await dualStack()
                restoredIPv4 = after.ipv4 == before.ipv4
                restoredIPv6 = after.ipv6 == before.ipv6
                if restoredIPv4 && restoredIPv6 { break }
            } catch {}
            if attempt < 3 { try await Task.sleep(nanoseconds: 850_000_000) }
        }
        print("APL_VPN_DUALSTACK_RESTORED_IPV4_\(restoredIPv4)_IPV6_\(restoredIPv6)")
        XCTAssertTrue(ipv4Receipt, "VPN must return authenticated IPv4-only HTTPS receipt")
        XCTAssertTrue(ipv6Receipt, "VPN must return authenticated IPv6-only HTTPS receipt")
        XCTAssertTrue(changedIPv4, "Real PacketTunnel must change the IPv4 external source")
        XCTAssertTrue(changedIPv6, "Real PacketTunnel must change the IPv6 external source")
        XCTAssertTrue(restoredIPv4 && restoredIPv6, "Both direct families must restore after VPN OFF")
#endif
    }


    /// In-process DNS snapshot: count only A, AAAA and tun2proxy's synthetic
    /// 198.18/15 addresses. Never emit actual DNS answers or hostnames.
    private func dnsFamilyCounts(_ publicHost: String) -> (Int32, Int, Int, Int) {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        let code = getaddrinfo(publicHost, nil, &hints, &result)
        defer { if let result { freeaddrinfo(result) } }
        guard code == 0 else { return (code, 0, 0, 0) }
        var v4 = 0
        var v6 = 0
        var synthetic = 0
        var cursor = result
        while let entry = cursor {
            let record = entry.pointee
            if record.ai_family == AF_INET {
                v4 += 1
                if let addr = record.ai_addr {
                    let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                    let isFake = withUnsafeBytes(of: ip) { raw in
                        raw.count >= 2 && raw[0] == 198 && (raw[1] == 18 || raw[1] == 19)
                    }
                    if isFake { synthetic += 1 }
                }
            }
            if record.ai_family == AF_INET6 { v6 += 1 }
            cursor = record.ai_next
        }
        return (0, v4, v6, synthetic)
    }

    /// Diagnostic of raw IPv4/IPv6 routes with TLS to PUBLIC literal IPs.
    /// Never changes owner preferences; entirely isolated from product scheme.
    func testBoundedAPLPacketTunnelLiteralIPv4IPv6RoutesAndRestore() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Physical device with existing VPN and dual IP path required")
#else
        let session = try await existingOffTunnel()
        let before: DualStack
        do {
            before = try await literalDualStack()
            let stable = try await literalDualStack()
            guard before == stable else { throw XCTSkip("Numeric direct IP baselines unstable") }
        } catch {
            throw XCTSkip("Numeric direct IPv4/IPv6 HTTPS baselines unavailable, no VPN started")
        }
        print("APL_VPN_LITERAL_IP_PREFLIGHT_BOTH_FAMILIES_OFF_PASS")

        var attempted = false
        var hostStop: DispatchWorkItem?
        defer {
            hostStop?.cancel()
            if attempted { session.stopVPNTunnel() }
        }
        attempted = true
        do {
            try session.startTunnel(options: [
                "requestedByUser": NSNumber(value: true),
                "qaStopAfterSeconds": NSNumber(value: 25)
            ])
        } catch {
            XCTFail("Bounded VPN start refused")
            return
        }
        let stop = DispatchWorkItem { session.stopVPNTunnel() }
        hostStop = stop
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 20, execute: stop
        )

        var connected = false
        for attempt in 0..<48 {
            let state = session.status
            if state == .connected { connected = true; break }
            if state == .invalid || (state == .disconnected && attempt >= 16) { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard connected else {
            XCTFail("PacketTunnel not connected, independent safety timers armed")
            return
        }
        print("APL_VPN_LITERAL_IP_TUN_CONNECTED_GUARDED_20_25")

        var receivedV4 = false
        var receivedV6 = false
        var changedV4 = false
        var changedV6 = false
        do {
            let origin = try await literalFamilyReceipt("https://1.1.1.1/cdn-cgi/trace", family: AF_INET)
            receivedV4 = true
            changedV4 = origin != before.ipv4
            print("APL_VPN_LITERAL_IPV4_HTTPS_RECEIPT_PASS_CHANGED_\(changedV4)")
        } catch {
            print("APL_VPN_LITERAL_IPV4_HTTPS_RECEIPT_FAILED_CODE_\((error as NSError).code)")
        }
        do {
            let origin = try await literalFamilyReceipt("https://[2606:4700:4700::1111]/cdn-cgi/trace", family: AF_INET6)
            receivedV6 = true
            changedV6 = origin != before.ipv6
            print("APL_VPN_LITERAL_IPV6_HTTPS_RECEIPT_PASS_CHANGED_\(changedV6)")
        } catch {
            print("APL_VPN_LITERAL_IPV6_HTTPS_RECEIPT_FAILED_CODE_\((error as NSError).code)")
        }

        hostStop?.cancel()
        session.stopVPNTunnel()
        var off = false
        for _ in 0..<40 {
            if session.status == .disconnected { off = true; break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        guard off else {
            XCTFail("VPN was not OFF after explicit stop; extension timer remains armed")
            return
        }
        print("APL_VPN_LITERAL_IP_TUN_EXPLICIT_OFF_CONFIRMED")

        var restoredV4 = false
        var restoredV6 = false
        for attempt in 1...3 {
            do {
                let after = try await literalDualStack()
                restoredV4 = after.ipv4 == before.ipv4
                restoredV6 = after.ipv6 == before.ipv6
                if restoredV4 && restoredV6 { break }
            } catch {}
            if attempt < 3 { try await Task.sleep(nanoseconds: 850_000_000) }
        }
        print("APL_VPN_LITERAL_IP_RESTORED_IPV4_\(restoredV4)_IPV6_\(restoredV6)")
        XCTAssertTrue(receivedV4, "Literal IPv4 HTTPS must complete through PacketTunnel")
        XCTAssertTrue(receivedV6, "Literal IPv6 HTTPS must complete through PacketTunnel")
        XCTAssertTrue(changedV4, "Literal IPv4 tunnel egress must differ from direct origin")
        XCTAssertTrue(changedV6, "Literal IPv6 tunnel egress must differ from direct origin")
        XCTAssertTrue(restoredV4 && restoredV6, "Both direct literal IP origins must restore")
#endif
    }


    /// Counts system DNS records before/during/after an explicitly bounded
    /// real PacketTunnel. DNS answers are not logged; unknown failure codes
    /// are reported only as numbers. This is diagnostic, not an acceptance PASS.
    func testBoundedAPLPacketTunnelDNSSyntheticAddressDiagnosis() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Requires physical iPhone and existing owner PacketTunnel")
#else
        let session = try await existingOffTunnel()
        let directA = dnsFamilyCounts("ipv4.icanhazip.com")
        let directDual = dnsFamilyCounts("httpbingo.org")
        guard directA.0 == 0 && directA.1 + directA.2 > 0,
              directDual.0 == 0 && directDual.1 + directDual.2 > 0 else {
            throw XCTSkip("Direct DNS baseline unavailable; no VPN started")
        }
        print("APL_DNS_DIAG_BASELINE_A_V4_\(directA.1)_V6_\(directA.2)_SYNTH_\(directA.3)")
        print("APL_DNS_DIAG_BASELINE_DUAL_V4_\(directDual.1)_V6_\(directDual.2)_SYNTH_\(directDual.3)")

        var started = false
        var stopJob: DispatchWorkItem?
        defer {
            stopJob?.cancel()
            if started { session.stopVPNTunnel() }
        }
        started = true
        try session.startTunnel(options: [
            "requestedByUser": NSNumber(value: true),
            "qaStopAfterSeconds": NSNumber(value: 25)
        ])
        let stop = DispatchWorkItem { session.stopVPNTunnel() }
        stopJob = stop
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 20, execute: stop
        )
        var connected = false
        for attempt in 0..<48 {
            let state = session.status
            if state == .connected { connected = true; break }
            if state == .invalid || (state == .disconnected && attempt >= 16) { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard connected else {
            XCTFail("PacketTunnel never reached Connected; independent kill timers armed")
            return
        }
        print("APL_DNS_DIAG_SYSTEM_PACKETTUNNEL_CONNECTED_GUARDED")
        let tunnelA = dnsFamilyCounts("ipv4.icanhazip.com")
        let tunnelDual = dnsFamilyCounts("httpbingo.org")
        print("APL_DNS_DIAG_TUN_A_CODE_\(tunnelA.0)_V4_\(tunnelA.1)_V6_\(tunnelA.2)_SYNTH_\(tunnelA.3)")
        print("APL_DNS_DIAG_TUN_DUAL_CODE_\(tunnelDual.0)_V4_\(tunnelDual.1)_V6_\(tunnelDual.2)_SYNTH_\(tunnelDual.3)")

        stopJob?.cancel()
        session.stopVPNTunnel()
        var off = false
        for _ in 0..<40 {
            if session.status == .disconnected { off = true; break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertTrue(off, "APL must return OFF after bounded DNS diagnosis")
        if off { print("APL_DNS_DIAG_PACKETTUNNEL_OFF_CONFIRMED") }
#endif
    }

#endif
}
