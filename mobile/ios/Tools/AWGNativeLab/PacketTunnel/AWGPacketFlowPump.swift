// Standalone AWG lab only. No production linkage or registration.
import Darwin
import Foundation
import NetworkExtension
#if APL_NATIVE_UNIFIED_GO_CANDIDATE
import APLUnifiedGo
#else
import APLAWGBridge
#endif

final class AWGPacketFlowPump: @unchecked Sendable {
    private let queue = DispatchQueue(label: "apl.awg.isolated.packet-flow")
    private let flow: NEPacketTunnelFlow
    private let onFailure: () -> Void
    private var token: UInt64 = 0
    private var retired = false
    private var timer: DispatchSourceTimer?
    private let mtu = 1280

    init(flow: NEPacketTunnelFlow, onFailure: @escaping () -> Void) {
        self.flow = flow
        self.onFailure = onFailure
    }

    func start(keys: Data, localIPv4: UInt32?, listen: UInt16, peer: UInt16,
               completion: @escaping (Bool) -> Void) {
        queue.async {
            guard !self.retired, self.token == 0, keys.count == 96 else { completion(false); return }
            var buffer = keys
            defer { buffer.resetBytes(in: 0..<buffer.count) }
            let generation = buffer.withUnsafeMutableBytes { raw in
                if let localIPv4 { return aplAWGBridgeStartLAN(localIPv4, raw.baseAddress, 96) }
                return aplAWGBridgeStart(0, listen, peer, raw.baseAddress, 96)
            }
            guard generation != 0 else { self.retired = true; completion(false); return }
            self.token = generation
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in self?.deliver(generation) }
            self.timer = timer
            timer.resume()
            self.read(generation)
            completion(true)
        }
    }

    private func active(_ generation: UInt64) -> Bool {
        !retired && token != 0 && token == generation
    }

    private func read(_ generation: UInt64) {
        guard active(generation) else { return }
        flow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            self.queue.async {
                guard self.active(generation) else { return }
                guard packets.count == protocols.count else { self.fail(generation); return }
                for (packet, proto) in zip(packets.prefix(32), protocols.prefix(32)) {
                    guard let byte = packet.first, packet.count <= self.mtu,
                          (byte >> 4 == 4 && proto.int32Value == AF_INET) ||
                          (byte >> 4 == 6 && proto.int32Value == AF_INET6) else { continue }
                    var copy = packet
                    let rc = copy.withUnsafeMutableBytes { raw in
                        aplAWGBridgePush(generation, raw.baseAddress, Int32(raw.count))
                    }
                    if rc == -2 { continue }
                    guard rc == Int32(packet.count) else { self.fail(generation); return }
                }
                self.read(generation)
            }
        }
    }

    private func deliver(_ generation: UInt64) {
        guard active(generation) else { return }
        var packets: [Data] = [], protocols: [NSNumber] = []
        var bytes = Data(count: mtu)
        for _ in 0..<32 {
            let n = bytes.withUnsafeMutableBytes { raw in
                aplAWGBridgePull(generation, raw.baseAddress, Int32(raw.count))
            }
            if n == 0 { break }
            guard n > 0, n <= mtu, let version = bytes.first.map({ $0 >> 4 }),
                  version == 4 || version == 6 else { fail(generation); return }
            packets.append(Data(bytes.prefix(Int(n))))
            protocols.append(NSNumber(value: version == 4 ? AF_INET : AF_INET6))
        }
        if !packets.isEmpty && !flow.writePackets(packets, withProtocols: protocols) {
            fail(generation)
        }
    }

    private func fail(_ generation: UInt64) {
        guard active(generation) else { return }
        retired = true
        timer?.cancel(); timer = nil
        onFailure()
    }

    func stop(completion: @escaping (Bool) -> Void) {
        queue.async {
            self.retired = true
            self.timer?.cancel(); self.timer = nil
            let old = self.token
            guard old != 0 else { completion(true); return }
            let ok = aplAWGBridgeStop(old) == 0
            if ok { self.token = 0 }
            completion(ok)
        }
    }
}
