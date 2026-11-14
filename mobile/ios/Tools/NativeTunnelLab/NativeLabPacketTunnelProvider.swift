// Build-only isolated NetworkExtension. Explicit synthetic QA options only.
// Not part of the production app, and never configured with owner profiles.
import Darwin
import Foundation
import NetworkExtension

private final class LabCounters: @unchecked Sendable {
    static let shared = LabCounters()
    private let lock = NSLock()
    private var values: [String:Int] = [:]
    func increment(_ key: String) { lock.lock(); values[key,default:0] += 1; lock.unlock() }
    func snapshot() -> [String:Int] { lock.lock(); defer { lock.unlock() }; return values }
}
import tun2proxy

final class NativeLabPacketTunnelProvider: NEPacketTunnelProvider {
    @MainActor private var lifecycle = XrayHandoffLifecycle()
    @MainActor private var starting = false
    @MainActor private var stopping = false
    @MainActor private var retired = false
    @MainActor private var engineStarted = false
    @MainActor private var xrayStarted = false
    @MainActor private var timeoutTask: Task<Void,Never>?
    private let queue = DispatchQueue(label:"apl.isolated.native.engine")
    private let gate = TunnelEngineExitGate()

    override func startTunnel(options: [String:NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            guard !starting, !stopping, !retired, lifecycle.phase == .idle else {
                completionHandler(NativeLabError.stage(3).safeNSError); return
            }
            starting = true
            defer { starting = false }
            do {
                try await startLab(options)
                completionHandler(nil)
            } catch {
                retired = true
                await drain()
                completionHandler((error as? NativeLabError)?.safeNSError ?? NativeLabError.stage(4).safeNSError)
            }
        }
    }

    @MainActor private func startLab(_ options: [String:NSObject]?) async throws {
        guard options?["aplNativeSyntheticQA"] as? String == "explicit-lab-v1",
              let link=options?["aplSyntheticLink"] as? String else { throw NativeLabError.stage(5) }
        let candidate = try VLESSRealityShareLink.parse(link)
        guard candidate.serverPort == 39882, candidate.serverName == "example.com",
              candidate.serverHost == "127.0.0.1" || candidate.serverHost == "192.168.1.80" else {
            throw NativeLabError.stage(6)
        }
        let config = try NativeLabRuntime.prepare(candidate,port:39879)
        let token = try lifecycle.begin()
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress:candidate.serverHost)
        let ipv4 = NEIPv4Settings(addresses:["192.0.2.177"],subnetMasks:["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress:"198.51.100.77",subnetMask:"255.255.255.255")]
        settings.ipv4Settings = ipv4
        settings.mtu = 1500
        // No default route, DNS, IPv6 or general LAN traffic in this lab.
        try await setTunnelNetworkSettings(settings)
        guard !stopping, !retired, lifecycle.phase == .starting,
              let fd=ExactLabTUNDescriptor.find(address:"192.0.2.177") else { throw NativeLabError.stage(7) }
        let plan = try XraySocksHandoffPlan.prepare(tunFD:Int(fd),socksPort:39879,dnsBypass:[])
        xrayStarted = true
        guard NativeLabRuntime.call("runXray",config:config) != nil, NativeLabRuntime.running == true else { throw NativeLabError.stage(8) }
        let generation = gate.begin()
        engineStarted = true
        tun2proxy_set_log_callback({ _, message, _ in
            guard let message else {return}
            let line=String(cString:message).lowercased()
            if line.contains("tcp") {LabCounters.shared.increment("tcp")}
            if line.contains("socks") {LabCounters.shared.increment("socks")}
            if line.contains("error") || line.contains("failed") {LabCounters.shared.increment("error")}
            if line.contains("connect") {LabCounters.shared.increment("connect")}
            if line.contains("198.51.100.77") {LabCounters.shared.increment("target")}
        },nil)
        let args = plan.tun2proxyArguments.replacingOccurrences(of:"--verbosity warn",with:"--verbosity debug")
        queue.async { [weak self] in
            guard let self, self.gate.isRunning(generation) else { return }
            _ = args.withCString { tun2proxy_run_with_cli_args($0,1500,true) }
            guard self.gate.markUnexpectedExit(generation) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.gate.shouldCancelTunnel(generation) else { return }
                try? self.lifecycle.failClosed(generation:token)
                self.retired = true
                self.cancelTunnelWithError(NativeLabError.stage(9).safeNSError)
            }
        }
        try await Task.sleep(nanoseconds:350_000_000)
        guard !stopping, !retired, gate.isRunning(generation) else { throw NativeLabError.stage(10) }
        try lifecycle.ready(generation:token)
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:20_000_000_000)
            guard !Task.isCancelled,let self,self.gate.isRunning(generation) else { return }
            self.retired = true
            self.cancelTunnelWithError(NativeLabError.stage(11).safeNSError)
        }
    }

    override func handleAppMessage(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard messageData == Data("apl-lab-counters-v1".utf8) else {completionHandler?(nil);return}
        completionHandler?(try? JSONSerialization.data(withJSONObject:LabCounters.shared.snapshot()))
    }

    override func stopTunnel(with reason: NEProviderStopReason,completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            retired = true
            await drain()
            completionHandler()
        }
    }

    @MainActor private func drain() async {
        // Multiple stop callbacks wait for the single in-progress cleanup.
        if stopping {
            while stopping { try? await Task.sleep(nanoseconds:20_000_000) }
            return
        }
        stopping = true
        defer { stopping = false }
        timeoutTask?.cancel(); timeoutTask=nil
        gate.invalidate()
        let token = lifecycle.generation
        _ = try? lifecycle.requestStop(generation:token)
        if engineStarted {
            do {
                try await TunnelEngineHandoff.stopAndDrain(engineQueue:queue,timeout:5) {
                    _ = tun2proxy_stop()
                }
                engineStarted=false
                tun2proxy_set_log_callback(nil,nil)
            } catch {
                try? lifecycle.failClosed(generation:token)
                // No retry/restart in this provider instance. OS owns TUN.
                cancelTunnelWithError(NativeLabError.stage(12).safeNSError)
            }
        }
        if xrayStarted {
            if NativeLabRuntime.call("stopXray") != nil, NativeLabRuntime.running == false {
                xrayStarted=false
            } else { try? lifecycle.failClosed(generation:token) }
        }
        if !engineStarted && !xrayStarted && lifecycle.phase == .stopping {
            try? lifecycle.drained(generation:token)
        }
        try? await setTunnelNetworkSettings(nil)
    }
}
