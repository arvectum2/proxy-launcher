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
    @MainActor private var exitChallenge: Int?
    @MainActor private var forcedExitRequested = false
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
        if let code=options?["aplLabExitChallenge"] as? NSNumber {
            guard (100000...999999).contains(code.intValue) else {throw NativeLabError.stage(5)}
            exitChallenge=code.intValue
        }
        let mode=options?["aplLabTransport"] as? String ?? "vless"
        let config:String
        let remote:String
        let dual:Bool
        if mode == "wg-dual" {
            // Standard WG synthetic fixture only; no AWG or user profile.
            config=try XrayWireGuardLabConfig.prepare(link,port:39879,dual:true,physical:true)
            remote="192.168.1.80"
            dual=true
            guard NativeLabRuntime.running == false,
                  (NativeLabRuntime.call("xrayVersion")?["data"] as? [String:Any])?["version"] as? String == "26.11.9",
                  NativeLabRuntime.call("testXray",config:config) != nil else {throw NativeLabError.stage(6)}
        } else if mode == "vless" {
            let candidate = try VLESSRealityShareLink.parse(link)
            guard candidate.serverPort == 39882, candidate.serverName == "example.com",
                  candidate.serverHost == "127.0.0.1" || candidate.serverHost == "192.168.1.80" else {
                throw NativeLabError.stage(6)
            }
            config=try NativeLabRuntime.prepare(candidate,port:39879)
            remote=candidate.serverHost
            dual=false
        } else {throw NativeLabError.stage(6)}
        let token = try lifecycle.begin()
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress:remote)
        let ipv4 = NEIPv4Settings(addresses:["192.0.2.177"],subnetMasks:["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress:"198.51.100.77",subnetMask:"255.255.255.255")]
        settings.ipv4Settings = ipv4
        if dual {
            let ipv6=NEIPv6Settings(addresses:["2001:db8:177::2"],networkPrefixLengths:[128])
            ipv6.includedRoutes=[NEIPv6Route(destinationAddress:"2001:db8:77::77",networkPrefixLength:128)]
            settings.ipv6Settings=ipv6
        }
        settings.mtu = dual ? 1280 : 1500
        // Only fixed synthetic host routes, no DNS or default routes.
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
            if (line.contains("198.51.100.77") || line.contains("2001:db8:77::77")) {LabCounters.shared.increment("target")}
        },nil)
        let args = plan.tun2proxyArguments.replacingOccurrences(of:"--verbosity warn",with:"--verbosity debug")
        queue.async { [weak self] in
            guard let self, self.gate.isRunning(generation) else { return }
            let rc = args.withCString { tun2proxy_run_with_cli_args($0,dual ? 1280 : 1500,true) }
            guard self.gate.markUnexpectedExit(generation) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.gate.shouldCancelTunnel(generation) else { return }
                try? self.lifecycle.failClosed(generation:token)
                self.retired = true
                // Fresh challenge only on actual native return after the one-shot request.
                let code = self.forcedExitRequested && rc == 0 ? (self.exitChallenge ?? 9) : 9
                self.cancelTunnelWithError(NativeLabError.stage(code).safeNSError)
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
        Task { @MainActor in
            if messageData == Data("apl-lab-counters-v1".utf8) {
                var values=LabCounters.shared.snapshot()
                var info=mach_task_basic_info()
                var count=mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
                let kr=withUnsafeMutablePointer(to:&info) {
                    $0.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {
                        task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count)
                    }
                }
                if kr == KERN_SUCCESS { values["rssBytes"]=Int(info.resident_size) }
                completionHandler?(try? JSONSerialization.data(withJSONObject:values))
                return
            }
            guard let code=exitChallenge, !forcedExitRequested, !stopping,
                  lifecycle.phase == .running, engineStarted,
                  messageData == Data(("apl-lab-exit-"+String(code)).utf8) else {
                completionHandler?(nil);return
            }
            forcedExitRequested=true
            // Do not invalidate the exit gate: this deliberately exercises the
            // native run-return path, rather than invoking stopTunnel.
            completionHandler?(Data("exit-requested".utf8))
            _ = tun2proxy_stop()
        }
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
