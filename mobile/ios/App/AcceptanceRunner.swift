#if DEBUG
import Darwin
import Foundation
import NetworkExtension

@MainActor
enum AcceptanceRunner {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["APL_ACCEPTANCE"] == "1" ||
        ProcessInfo.processInfo.arguments.contains("--apl-acceptance")
    }

    static func runIfRequested() async {
        guard isEnabled else { return }
        resetLog()

        let env = ProcessInfo.processInfo.environment
        let host = env["APL_ACCEPTANCE_HOST"] ?? "192.168.1.80"
        let primaryPort = Int(env["APL_ACCEPTANCE_PRIMARY_PORT"] ?? "") ?? 18080
        let secondaryPort = Int(env["APL_ACCEPTANCE_SECONDARY_PORT"] ?? "") ?? 18081
        let primaryID = UUID(uuidString: "A1111111-1111-4111-8111-111111111111")!
        let secondaryID = UUID(uuidString: "B2222222-2222-4222-8222-222222222222")!

        var passed = true
        do {
            let store = try ProfileStore()
            let telemetry = TelemetryStore()
            telemetry.clear()

            for profile in store.listProfiles() {
                try? store.delete(id: profile.id)
            }

            let primary = ProxyProfile(
                id: primaryID,
                name: "Acceptance Primary",
                host: host,
                port: primaryPort,
                type: .http
            )
            let secondary = ProxyProfile(
                id: secondaryID,
                name: "Acceptance Secondary",
                host: host,
                port: secondaryPort,
                type: .http
            )

            try store.save(primary, password: nil, makeActive: false)
            try store.save(secondary, password: nil, makeActive: false)
            store.automaticSelection = true
            store.selectedProfileID = nil
            store.primaryProfileID = primaryID
            store.restorePolicy = .returnToPrimary
            store.siteExclusions = ["example.net"]
            store.lastAutoProfileID = nil
            store.lastFailoverAt = nil
            store.clearRecentlyFailed()

            log("APL_ACCEPTANCE SEEDED host=\(host) primary=\(primaryPort) secondary=\(secondaryPort) exclusion=example.net")

            let vpn = VPNController()
            await vpn.prepare()
            log("APL_ACCEPTANCE PREPARED status=\(vpn.status.rawValue) detail=\(vpn.detail)")

            try await vpn.connect()
            guard await waitForStatus(vpn, .connected, timeout: 25) else {
                log("APL_ACCEPTANCE CONNECT FAIL status=\(vpn.status.rawValue) detail=\(vpn.detail)")
                Darwin.exit(21)
            }
            log("APL_ACCEPTANCE CONNECT PASS")

            if let exclusions = await waitForEvent(telemetry, type: "debug exclusions applied", profileName: "Acceptance Primary", timeout: 10) {
                log("APL_ACCEPTANCE EXCLUSIONS PASS \(exclusions.detail ?? "")")
            } else {
                log("APL_ACCEPTANCE EXCLUSIONS FAIL no provider confirmation")
                passed = false
            }

            passed = await networkCheck(label: "PRIMARY_TUNNEL", url: "https://example.org/") && passed
            passed = await networkCheck(label: "EXCLUDED_DIRECT", url: "https://example.net/") && passed

            if let failover = await waitForEvent(telemetry, type: "failover", profileName: "Acceptance Secondary", timeout: 50) {
                log("APL_ACCEPTANCE FAILOVER PASS \(failover.detail ?? "")")
                passed = await networkCheck(label: "SECONDARY_TUNNEL", url: "https://example.org/") && passed
            } else {
                log("APL_ACCEPTANCE FAILOVER FAIL timeout")
                passed = false
            }

            if let restored = await waitForEvent(telemetry, type: "primary restored", profileName: "Acceptance Primary", timeout: 65) {
                log("APL_ACCEPTANCE RESTORE PASS \(restored.detail ?? "")")
                passed = await networkCheck(label: "RESTORED_TUNNEL", url: "https://example.org/") && passed
            } else {
                log("APL_ACCEPTANCE RESTORE FAIL timeout")
                passed = false
            }

            vpn.disconnect()
            if await waitForStatus(vpn, .disconnected, timeout: 12) {
                log("APL_ACCEPTANCE DISCONNECT PASS")
            } else {
                log("APL_ACCEPTANCE DISCONNECT FAIL status=\(vpn.status.rawValue)")
                passed = false
            }

            log(passed ? "APL_ACCEPTANCE OVERALL PASS" : "APL_ACCEPTANCE OVERALL FAIL")
            fflush(stdout)
            Darwin.exit(passed ? 0 : 22)
        } catch {
            log("APL_ACCEPTANCE ERROR \(error.localizedDescription)")
            fflush(stdout)
            Darwin.exit(23)
        }
    }

    private static func waitForStatus(_ vpn: VPNController, _ expected: NEVPNStatus, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if vpn.status == expected { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return vpn.status == expected
    }

    private static func waitForEvent(
        _ telemetry: TelemetryStore,
        type: String,
        profileName: String,
        timeout: TimeInterval
    ) async -> TunnelEvent? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let event = telemetry.list(limit: 40).first(where: {
                $0.type == type && $0.profileName == profileName
            }) {
                return event
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return nil
    }

    private static func networkCheck(label: String, url: String) async -> Bool {
        guard let url = URL(string: url) else {
            log("APL_ACCEPTANCE NETWORK \(label) FAIL bad-url")
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let ok = (200...399).contains(status)
            log("APL_ACCEPTANCE NETWORK \(label) \(ok ? "PASS" : "FAIL") status=\(status)")
            return ok
        } catch {
            log("APL_ACCEPTANCE NETWORK \(label) FAIL \(error.localizedDescription)")
            return false
        }
    }

    private static var logURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("apl-acceptance.log")
    }

    private static func resetLog() {
        guard let url = logURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func log(_ message: String) {
        fputs(message + "\n", stderr)
        guard let url = logURL, let data = (message + "\n").data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }

}
#endif
