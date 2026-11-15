#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_AWG_CANDIDATE && APL_NATIVE_UNIFIED_GO_CANDIDATE && APL_NATIVE_AWG_PRODUCT_BRIDGE
#if APL_NATIVE_SYNTHETIC_RUNTIME
#error("Product AWG bridge must not coexist with synthetic runtime")
#endif
import Darwin
import Foundation
import NetworkExtension
import APLUnifiedGo

private final class AWGProductCompletion:@unchecked Sendable {
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Bool,Never>?
    init(_ continuation:CheckedContinuation<Bool,Never>){self.continuation=continuation}
    func finish(_ result:Bool){lock.lock();let reply=continuation;continuation=nil;lock.unlock();reply?.resume(returning:result)}
}

/// Product-shaped packetFlow adapter. No manager, route installation, or
/// automatic start caller. The provider must separately prove underlay and
/// own a validated route plan before activation.
final class NativeAWGProductFlow: @unchecked Sendable {
    enum Failure:Error {case invalidPlan, unavailable, notDrained}
    private let queue=DispatchQueue(label:"apl.awg.product.packet-flow")
    private let flow:NEPacketTunnelFlow
    private let plan:NativeTunnelRoutePlan
    private var mtu:Int {plan.mtu}
    private let onFailure:()->Void
    private var token:UInt64=0
    private var starting=false,started=false,retired=false
    private var timer:DispatchSourceTimer?
    private let cancellationLock=NSLock()
    private var stopRequested=false
    private var cancellationRequested:Bool {cancellationLock.lock();defer{cancellationLock.unlock()};return stopRequested}
    private func requestStop(){cancellationLock.lock();stopRequested=true;cancellationLock.unlock()}

    init(flow:NEPacketTunnelFlow,plan:NativeTunnelRoutePlan,onFailure:@escaping()->Void)throws {
        guard plan.provider == .standaloneAWG,(1280...1500).contains(plan.mtu),plan.excludedRoutes.isEmpty else{throw Failure.invalidPlan}
        self.flow=flow;self.plan=plan;self.onFailure=onFailure
    }

    /// Compile, construct and dispose the exact down-state device. Safe to
    /// use from ordinary credential validation; does not use packetFlow.
    static func validateDown(route:NativeValidationRoute,configuration:Data)throws {
        guard case .wireGuard(let plan)=route,plan.provider == .standaloneAWG else{throw Failure.invalidPlan}
        let token=try prepare(configuration,plan:plan)
        guard aplAWGProductStop(token)==0 else{throw Failure.notDrained}
    }
    private static func prepare(_ configuration:Data,plan:NativeTunnelRoutePlan)throws->UInt64 {
        let mtu=plan.mtu
        guard plan.provider == .standaloneAWG,plan.remotePort>0 else{throw Failure.invalidPlan}
        guard !configuration.isEmpty,configuration.count<=4096,(1280...1500).contains(mtu) else{throw Failure.invalidPlan}
        var bytes=configuration
        defer{bytes.resetBytes(in:0..<bytes.count)}
        var host=Data(plan.remoteAddress.utf8)
        let token=host.withUnsafeMutableBytes{address in bytes.withUnsafeMutableBytes{raw in aplAWGProductPrepare(raw.baseAddress,Int32(raw.count),Int32(mtu),address.baseAddress,Int32(address.count),plan.remotePort)}}
        guard token != 0 else{throw Failure.unavailable};return token
    }

    /// Queue ownership includes ambiguous starts: retain token for stop.
    func start(configuration:Data,completion:@escaping(Bool)->Void) {
        queue.async {
            guard !self.cancellationRequested,!self.retired,!self.starting,!self.started,self.token==0 else{completion(false);return}
            self.starting=true;defer{self.starting=false}
            do {
                let token=try Self.prepare(configuration,plan:self.plan)
                self.token=token
                guard !self.cancellationRequested else{completion(false);return}
                guard aplAWGProductStart(token)==0 else{self.fail();completion(false);return}
                guard !self.cancellationRequested else{completion(false);return}
                self.started=true
                let t=DispatchSource.makeTimerSource(queue:self.queue)
                t.schedule(deadline:.now(),repeating:.milliseconds(10),leeway:.milliseconds(2))
                t.setEventHandler{[weak self] in self?.deliver(token)}
                self.timer=t;t.resume();self.read(token);completion(true)
            }catch{self.retired=true;completion(false)}
        }
    }
    private func active(_ generation:UInt64)->Bool {!cancellationRequested && !retired && started && token==generation && generation != 0}
    private func fail(){retired=true;started=false;timer?.cancel();timer=nil;onFailure()}
    private func read(_ generation:UInt64) {
        guard active(generation) else{return}
        flow.readPackets{[weak self] packets,protocols in
            guard let self else{return}
            self.queue.async {
                guard self.active(generation) else{return}
                guard packets.count==protocols.count else{self.fail();return}
                for (packet,proto) in zip(packets.prefix(32),protocols.prefix(32)){
                    guard let first=packet.first,packet.count<=self.mtu,
                          (first>>4==4 && proto.int32Value==AF_INET) || (first>>4==6 && proto.int32Value==AF_INET6) else{continue}
                    var data=packet
                    let count=data.withUnsafeMutableBytes{aplAWGProductPush(generation,$0.baseAddress,Int32($0.count))}
                    if count == -2 {continue}
                    guard count==Int32(packet.count) else{self.fail();return}
                }
                self.read(generation)
            }
        }
    }
    private func deliver(_ generation:UInt64){
        guard active(generation) else{return}
        var packets:[Data]=[],protocols:[NSNumber]=[],buffer=Data(count:mtu)
        for _ in 0..<32 {
            let n=buffer.withUnsafeMutableBytes{aplAWGProductPull(generation,$0.baseAddress,Int32($0.count))}
            if n==0{break}
            guard n>0,n<=mtu,let version=buffer.first.map({$0>>4}),version==4 || version==6 else{fail();return}
            packets.append(Data(buffer.prefix(Int(n))));protocols.append(NSNumber(value:version==4 ? AF_INET:AF_INET6))
        }
        if !packets.isEmpty && !flow.writePackets(packets,withProtocols:protocols){fail()}
    }
    /// A timeout is not a drain receipt. Owner retains this flow and retries
    /// stop until native closure completes; never start a second provider.
    func startWithDeadline(configuration:Data)async -> Bool {
        let result=await withCheckedContinuation { continuation in
            let reply=AWGProductCompletion(continuation)
            start(configuration:configuration){reply.finish($0)}
            DispatchQueue.global().asyncAfter(deadline:.now()+5){reply.finish(false)}
        }
        if !result {requestStop()}
        return result && !cancellationRequested
    }
    func stopWithDeadline()async -> Bool {
        await withCheckedContinuation { continuation in
            let reply=AWGProductCompletion(continuation)
            stop{reply.finish($0)}
            DispatchQueue.global().asyncAfter(deadline:.now()+5){reply.finish(false)}
        }
    }

    func cancelPendingStart(){requestStop()}
    func stop(completion:@escaping(Bool)->Void){
        requestStop()
        queue.async {
            self.retired=true;self.started=false;self.timer?.cancel();self.timer=nil
            guard self.token != 0 else{completion(true);return}
            let ok=aplAWGProductStop(self.token)==0
            if ok{self.token=0}
            completion(ok)
        }
    }
}
#endif
