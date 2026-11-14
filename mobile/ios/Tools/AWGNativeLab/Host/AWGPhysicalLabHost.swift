// Separate unsigned synthetic lab. Normal launches never alter VPN settings.
import Foundation
import SwiftUI
import NetworkExtension
import Network

private final class AWGProbeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }
    func finish(_ data: Data?) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(returning: data)
    }
}

@MainActor final class AWGPhysicalLabModel: ObservableObject {
    private static let provider = "ru.arvectum.proxylauncher.lab.awgcompile.PacketTunnel"
    private static let marker = "APL standalone AWG synthetic QA v1"
    private var consumed = false
    @Published private(set) var status = "No test requested"
    private struct Request: Decodable {
        let runID: UUID
        let action: String
        let keys: Data?
        let localIPv4: UInt32?
        let probe: String?
        let nonce: String?
    }
    private enum LabError: Error { case conflict, invalid }
    private func owned(_ manager: NETunnelProviderManager) -> Bool {
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return false }
        return proto.providerBundleIdentifier == Self.provider && proto.providerConfiguration?["labOwner"] as? String == Self.marker
    }
    private func profile(create: Bool) async throws -> NETunnelProviderManager? {
        let all = try await NETunnelProviderManager.loadAllFromPreferences()
        let named = all.filter { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.provider }
        guard named.count <= 1, named.allSatisfy(owned), all.filter({ !owned($0) }).allSatisfy({ $0.connection.status == .invalid || $0.connection.status == .disconnected }) else { throw LabError.conflict }
        if let existing = named.first { return existing }
        guard create else { return nil }
        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.provider
        proto.serverAddress = "Synthetic AWG only"
        proto.providerConfiguration = ["labOwner": Self.marker]
        manager.protocolConfiguration = proto
        manager.localizedDescription = Self.marker
        manager.isEnabled = true
        manager.isOnDemandEnabled = false
        status = "Confirm isolated AWG VPN permission on iPhone"
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        guard owned(manager) else { throw LabError.conflict }
        return manager
    }
    private func off(_ manager: NETunnelProviderManager) -> Bool {
        manager.connection.status == .disconnected || manager.connection.status == .invalid
    }
    private func stop(_ manager: NETunnelProviderManager, remove: Bool) async -> Bool {
        guard owned(manager) else { return false }
        if !off(manager) { manager.connection.stopVPNTunnel() }
        for _ in 0..<100 {
            if off(manager) {
                guard remove else { return true }
                do {
                    try await manager.removeFromPreferences()
                    let remaining = try await NETunnelProviderManager.loadAllFromPreferences()
                    return !remaining.contains(where: owned)
                } catch { return false }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }
    private func probe(kind: String, nonce: String) async -> Bool {
        let host = kind.hasSuffix("4") ? "192.0.2.2" : "2001:db8::2"
        let udp = kind.hasPrefix("udp")
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 39892, using: udp ? .udp : .tcp)
        let queue = DispatchQueue(label: "apl.awg.synthetic.probe")
        let reply: Data? = await withCheckedContinuation { continuation in
            let gate = AWGProbeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    connection.send(content: Data(nonce.utf8), completion: .contentProcessed { error in
                        guard error == nil else { gate.finish(nil); return }
                        if udp {
                            connection.receiveMessage { data, _, _, error in gate.finish(error == nil ? data : nil) }
                        } else {
                            connection.receive(minimumIncompleteLength: 52, maximumLength: 52) { data, _, _, error in gate.finish(error == nil ? data : nil) }
                        }
                    })
                case .failed, .cancelled: gate.finish(nil)
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + 4) { gate.finish(nil); connection.cancel() }
            connection.start(queue: queue)
        }
        connection.cancel()
        return reply == Data(("APL:" + nonce).utf8)
    }
    private func write(_ value: [String: Any], to url: URL) {
        if let data = try? JSONSerialization.data(withJSONObject: value) { try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }
    func runAuthorized() async {
        guard !consumed, ProcessInfo.processInfo.arguments.contains("--apl-authorized-awg-qa") else { return }
        consumed = true
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = folder.appendingPathComponent("awg-lab-input.json")
        let output = folder.appendingPathComponent("awg-lab-result.json")
        try? FileManager.default.removeItem(at: output)
        guard let handle = try? FileHandle(forReadingFrom: input) else { return }
        let raw = try? handle.read(upToCount: 4097); try? handle.close(); try? FileManager.default.removeItem(at: input)
        guard let raw, raw.count <= 4096, let request = try? JSONDecoder().decode(Request.self, from: raw) else { return }
        var result: [String: Any] = ["runID": request.runID.uuidString, "prepared": false, "connected": false, "receipt": false, "retainedOff": false, "cleaned": false]
        defer { write(result, to: output) }
        do {
            switch request.action {
            case "prepare":
                guard request.keys == nil, request.nonce == nil, let manager = try await profile(create: true), owned(manager), manager.isEnabled, !manager.isOnDemandEnabled, manager.connection.status == .disconnected else { throw LabError.conflict }
                result["prepared"] = true; status = "Prepared; VPN OFF"
            case "cleanup":
                guard request.keys == nil, request.nonce == nil else { throw LabError.invalid }
                if let manager = try await profile(create: false) { result["cleaned"] = await stop(manager, remove: true) }
                else { result["cleaned"] = true }
                status = "Cleanup finished; verify receipt"
            case "run":
                guard let keys = request.keys, keys.count == 96, let ip = request.localIPv4, ip >> 8 == 0xc0a801, (1...254).contains(ip & 255), let kind = request.probe, ["tcp4", "tcp6", "udp4", "udp6"].contains(kind), let nonce = request.nonce, nonce.utf8.count == 48, nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }), let manager = try await profile(create: false), owned(manager), manager.isEnabled, !manager.isOnDemandEnabled, manager.connection.status == .disconnected else { throw LabError.invalid }
                do {
                    try manager.connection.startVPNTunnel(options: ["aplAWGFixture": "explicit-lan-lab-v1" as NSString, "aplAWGKeys": keys as NSData, "aplAWGLocalIPv4": NSNumber(value: ip)])
                    for _ in 0..<100 {
                        if manager.connection.status == .connected { break }
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    let connected = manager.connection.status == .connected
                    result["connected"] = connected
                    if connected { let received = await probe(kind: kind, nonce: nonce); result["receipt"] = received && manager.connection.status == .connected }
                } catch { status = "Start or probe failed" }
                result["retainedOff"] = await stop(manager, remove: false)
                status = "Test finished; verify independent peer and OFF receipt"
            default: throw LabError.invalid
            }
        } catch { status = "Lab request rejected or failed" }
    }
}

@main struct AWGPhysicalLabHost: App {
    @StateObject private var model = AWGPhysicalLabModel()
    var body: some Scene { WindowGroup { VStack(spacing: 12) { Text("Isolated AWG QA"); Text(model.status) }.task { await model.runAuthorized() } } }
}
