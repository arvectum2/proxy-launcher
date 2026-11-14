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
    @MainActor private var retired = false
    @MainActor private var started = false
    @MainActor private var pump: AWGPacketFlowPump?
    private func failure(_ code: Int) -> NSError {
        NSError(domain: "APL.IsolatedAWGLab", code: code)
    }
    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            guard !retired, !started,
                  options?["aplAWGFixture"] as? String == "explicit-loopback-lab-v1",
                  let keys = options?["aplAWGKeys"] as? Data, keys.count == 96 else {
                completionHandler(failure(1)); return
            }
            started = true
            let once = AWGLabOnce()
            let finish: (Error?) -> Void = { error in
                if once.take() { completionHandler(error) }
            }
            let timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled, let self, once.take() else { return }
                self.retired = true
                completionHandler(self.failure(2))
                self.cancelTunnelWithError(self.failure(2))
            }
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
            let v4 = NEIPv4Settings(addresses: ["192.0.2.1"], subnetMasks: ["255.255.255.255"])
            v4.includedRoutes = [NEIPv4Route(destinationAddress: "192.0.2.2", subnetMask: "255.255.255.255")]
            settings.ipv4Settings = v4
            let v6 = NEIPv6Settings(addresses: ["2001:db8::1"], networkPrefixLengths: [128])
            v6.includedRoutes = [NEIPv6Route(destinationAddress: "2001:db8::2", networkPrefixLength: 128)]
            settings.ipv6Settings = v6
            settings.mtu = 1280
            do { try await setTunnelNetworkSettings(settings) }
            catch { retired = true; timeout.cancel(); finish(failure(3)); return }
            guard !retired else { try? await setTunnelNetworkSettings(nil); timeout.cancel(); finish(failure(4)); return }
            let bridge = AWGPacketFlowPump(flow: packetFlow) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.retired = true
                    self.cancelTunnelWithError(self.failure(5))
                }
            }
            pump = bridge
            bridge.start(keys: keys, listen: 39890, peer: 39891) { ok in
                Task { @MainActor in
                    timeout.cancel()
                    guard ok, !self.retired else {
                        self.retired = true
                        finish(self.failure(6)); self.cancelTunnelWithError(self.failure(6)); return
                    }
                    finish(nil) // Engine started, NOT a verified peer handshake.
                }
            }
        }
    }
    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            retired = true
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
