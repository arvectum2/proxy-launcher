// Build-only provider. Fixed TEST-NET host routes, no default routes,
// DNS, production credentials, App Group or automatic VPN registration.
import Foundation
import NetworkExtension

private final class AWGLabOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }; used = true; return true
    }
}

final class AWGIsolatedPacketTunnelProvider: NEPacketTunnelProvider {
    @MainActor private var control = TransportNativeControlState()
    @MainActor private var retired = false
    @MainActor private var started = false
    @MainActor private var pump: AWGPacketFlowPump?
    @MainActor private var lifetime: Task<Void, Never>?
    private func failure(_ code: Int) -> NSError {
        NSError(domain: "APL.IsolatedAWGLab", code: code)
    }
    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            guard !retired, !started,
                  let fixture = options?["aplAWGFixture"] as? String,
                  ["explicit-loopback-lab-v1", "explicit-lan-lab-v1"].contains(fixture),
                  let keys = options?["aplAWGKeys"] as? Data, keys.count == 96 else {
                completionHandler(failure(1)); return
            }
            let localIPv4: UInt32?
            if fixture == "explicit-lan-lab-v1" {
                guard let address = options?["aplAWGLocalIPv4"] as? NSNumber,
                      address.int64Value >= 0, address.int64Value <= Int64(UInt32.max),
                      address.uint32Value >> 8 == 0xc0a801,
                      (1...254).contains(address.uint32Value & 255) else {
                    completionHandler(failure(1)); return
                }
                localIPv4 = address.uint32Value
            } else { localIPv4 = nil }
            if let raw = options?["aplNativeIdentity"] {
                guard let data = raw as? Data, let identity = try? TransportNativeCodec.decode(TransportNativeIdentity.self, data),
                      (try? control.bind(identity, provider: "standalone-awg")) != nil else {
                    completionHandler(failure(1)); return
                }
            }
            started = true
            let once = AWGLabOnce()
            let finish: (Error?) -> Void = { error in
                if once.take() { completionHandler(error) }
            }
            let timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled, let self, once.take() else { return }
                self.retired = true; self.control.fail()
                completionHandler(self.failure(2))
                self.cancelTunnelWithError(self.failure(2))
            }
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: localIPv4 == nil ? "127.0.0.1" : "192.168.1.80")
            let v4 = NEIPv4Settings(addresses: ["192.0.2.1"], subnetMasks: ["255.255.255.255"])
            v4.includedRoutes = [NEIPv4Route(destinationAddress: "192.0.2.2", subnetMask: "255.255.255.255")]
            settings.ipv4Settings = v4
            let v6 = NEIPv6Settings(addresses: ["2001:db8::1"], networkPrefixLengths: [128])
            v6.includedRoutes = [NEIPv6Route(destinationAddress: "2001:db8::2", networkPrefixLength: 128)]
            settings.ipv6Settings = v6
            settings.mtu = 1280
            do { try await setTunnelNetworkSettings(settings) }
            catch { retired = true; control.fail(); timeout.cancel(); finish(failure(3)); return }
            guard !retired else { try? await setTunnelNetworkSettings(nil); timeout.cancel(); finish(failure(4)); return }
            let bridge = AWGPacketFlowPump(flow: packetFlow) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.retired = true; self.control.fail()
                    self.cancelTunnelWithError(self.failure(5))
                }
            }
            pump = bridge
            bridge.start(keys: keys, localIPv4: localIPv4, listen: 39890, peer: 39891) { ok in
                Task { @MainActor in
                    timeout.cancel()
                    guard ok, !self.retired else {
                        self.retired = true; self.control.fail()
                        finish(self.failure(6)); self.cancelTunnelWithError(self.failure(6)); return
                    }
                    self.lifetime = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 20_000_000_000)
                        guard !Task.isCancelled, let self, !self.retired else { return }
                        self.retired = true
                        self.cancelTunnelWithError(self.failure(9))
                    }
                    if self.control.identity != nil { try? self.control.ready() }
                    finish(nil) // Engine started, NOT a verified peer handshake.
                }
            }
        }
    }
    // Explicit stop handshake retains host routes until OS teardown. A
    // query cannot invent identity; a native close callback proves drain.
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        Task { @MainActor in
            guard let request = try? TransportNativeCodec.decode(TransportNativeRequest.self, messageData),
                  (try? control.response(to: request)) != nil else { completionHandler?(nil); return }
            if request.action == .drain, control.state == .ready, !retired, let pump {
                retired = true
                lifetime?.cancel(); lifetime = nil
                try? control.beginDrain()
                pump.stop { ok in
                    Task { @MainActor in
                        if ok { try? self.control.finishDrain() }
                        else { self.control.fail(); self.cancelTunnelWithError(self.failure(8)) }
                        let response = try? self.control.response(to: request)
                        completionHandler?(response.flatMap { try? TransportNativeCodec.encode($0) })
                    }
                }
                return
            }
            let response = try? control.response(to: request)
            completionHandler?(response.flatMap { try? TransportNativeCodec.encode($0) })
        }
    }
    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            retired = true
            lifetime?.cancel(); lifetime = nil
            if control.identity != nil && control.state != .drained { control.fail() }
            let once = AWGLabOnce()
            let finish = { if once.take() { completionHandler() } }
            let timeout = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                self.cancelTunnelWithError(self.failure(7))
                finish() // No native-drained claim on timeout.
            }
            guard let pump else {
                try? await setTunnelNetworkSettings(nil)
                timeout.cancel(); finish(); return
            }
            pump.stop { ok in
                Task { @MainActor in
                    if !ok { self.cancelTunnelWithError(self.failure(8)) }
                    try? await self.setTunnelNetworkSettings(nil)
                    timeout.cancel(); finish()
                }
            }
        }
    }
}
