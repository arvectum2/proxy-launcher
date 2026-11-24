// Isolated QA extension only; never loads owner profiles. Full-route variant has a synthetic-only egress guard.
import Darwin
import Foundation
import NetworkExtension
#if APL_PROVIDER_SCOPED_TUN_QA
import tun2proxy
#endif

final class NativeLabPacketTunnelProvider: NEPacketTunnelProvider {
    private var started=false
    private var consumed=false
    private var challenge:String?
    private var deadline:Task<Void,Never>?
    #if APL_PROVIDER_SCOPED_TUN_QA
    private let engineQueue=DispatchQueue(label:"apl.qa.scoped.tun")
    private let exitGate=TunnelEngineExitGate()
    private var rustStarted=false
    private var metricsStarted=false
    #endif
    override func startTunnel(options:[String:NSObject]?,completionHandler:@escaping(Error?)->Void) {
        Task { @MainActor in
            do {
                guard !started,!consumed,
                    options?["aplNativeSyntheticQA"] as? String == "explicit-lab-v1",
                    options?["aplLabTransport"] as? String == "vless-product-direct",
                    let link=options?["aplSyntheticLink"] as? String,
                    let nonce=options?["aplProviderNonce"] as? String,
                    nonce.utf8.count==40,nonce.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),
                    link.utf8.count<=4096 else {throw NativeLabError.stage(21)}
                let candidate=try VLESSRealityShareLink.parse(link)
                guard candidate.serverHost=="192.168.1.80",candidate.serverPort==39882,
                    candidate.serverName=="example.com",if_nametoindex("en0") != 0,
                    NativeLabRuntime.running==false,
                    (NativeLabRuntime.call("xrayVersion")?["data"] as? [String:Any])?["version"] as? String=="26.11.9"
                    else {throw NativeLabError.stage(22)}
                let raw=try XrayVLESSRuntimeConfig.compileValidatedCandidate(candidate,socksPort:39879,datagramReview:true)
                let bound=try XrayVLESSRuntimeConfig.bindPhysicalUnderlay(raw,interfaceName:"en0",expectedAddress:"192.168.1.80",expectedPort:39882)
                #if APL_PROVIDER_FULL_ROUTE_QA
                let guarded=try FullRouteGuard.restrict(bound)
                #else
                let guarded=bound
                #endif
                guard let config=String(data:guarded,encoding:.utf8),
                    NativeLabRuntime.call("testXray",config:config) != nil,
                    NativeLabRuntime.running==false else {throw NativeLabError.stage(23)}
                let settings=NEPacketTunnelNetworkSettings(tunnelRemoteAddress:"192.168.1.80")
                let ipv4=NEIPv4Settings(addresses:["192.0.2.177"],subnetMasks:["255.255.255.255"])
                #if APL_PROVIDER_FULL_ROUTE_QA
                guard NativeExactTunnelDescriptor.interfaces(address:"192.0.2.177")?.isEmpty==true,
                      NativeExactTunnelDescriptor.interfaces(address:"2001:db8:177::2")?.isEmpty==true else{throw NativeLabError.stage(28)}
                ipv4.includedRoutes=[NEIPv4Route.default()]
                ipv4.excludedRoutes=[]
                let v6=NEIPv6Settings(addresses:["2001:db8:177::2"],networkPrefixLengths:[128])
                v6.includedRoutes=[NEIPv6Route(destinationAddress:"::",networkPrefixLength:1),NEIPv6Route(destinationAddress:"8000::",networkPrefixLength:1)]
                v6.excludedRoutes=[]
                settings.ipv6Settings=v6
                let dns=NEDNSSettings(servers:["1.1.1.1","8.8.8.8"])
                dns.matchDomains=[""];dns.matchDomainsNoSearch=true
                settings.dnsSettings=dns
                #else
                ipv4.includedRoutes=[NEIPv4Route(destinationAddress:"198.51.100.77",subnetMask:"255.255.255.255")]
                #endif
                settings.ipv4Settings=ipv4
                settings.mtu=1500
                #if APL_PROVIDER_FULL_ROUTE_QA
                // Bound the full-route window from before installing routes.
                deadline=Task { @MainActor [weak self] in
                    do{try await Task.sleep(nanoseconds:20_000_000_000)}catch{return}
                    guard !Task.isCancelled,let self else{return}
                    self.consumed=true;self.challenge=nil
                    self.cancelTunnelWithError(NativeLabError.stage(26).safeNSError)
                }
                #endif
                try await setTunnelNetworkSettings(settings)
                guard !consumed else {throw NativeLabError.stage(24)}
                started=true
                guard NativeLabRuntime.call("runXray",config:config) != nil,
                      NativeLabRuntime.running==true else {throw NativeLabError.stage(25)}
                #if APL_PROVIDER_SCOPED_TUN_QA
                #if APL_PROVIDER_FULL_ROUTE_QA
                guard let fd=NativeExactTunnelDescriptor.find(address:"192.0.2.177",ipv6:"2001:db8:177::2") else{throw NativeLabError.stage(28)}
                #else
                guard let fd=ExactLabTUNDescriptor.find(address:"192.0.2.177") else{throw NativeLabError.stage(28)}
                #endif
                let handoff=try XraySocksHandoffPlan.prepare(tunFD:Int(fd),socksPort:39879,dnsBypass:[],exactDNS:true)
                guard let identity=ScopedTUNMetrics.descriptorIdentity(fd) else{throw NativeLabError.stage(28)}
                ScopedTUNMetrics.shared.start()
                metricsStarted=true
                ScopedTUNMetrics.shared.increment("descriptorMatchedBefore")
                if ProviderSOCKSProbe.greetingOnly() {
                    ScopedTUNMetrics.shared.increment("localSOCKSGreeting")
                }
                let token=exitGate.begin(),gate=exitGate
                rustStarted=true
                engineQueue.async { [weak self] in
                    guard gate.isRunning(token) else{return}
                    #if APL_PROVIDER_FULL_ROUTE_QA
                    let args=handoff.tun2proxyArguments
                    #else
                    let args=handoff.tun2proxyArguments.replacingOccurrences(of:"--verbosity warn",with:"--verbosity debug")
                    #endif
                    _=args.withCString{tun2proxy_run_with_cli_args($0,1500,true)}
                    guard gate.markUnexpectedExit(token) else{return}
                    Task { @MainActor [weak self] in
                        guard gate.shouldCancelTunnel(token) else{return}
                        self?.cancelTunnelWithError(NativeLabError.stage(29).safeNSError)
                    }
                }
                try await Task.sleep(nanoseconds:350_000_000)
                guard gate.isRunning(token),!consumed else{throw NativeLabError.stage(30)}
                if ScopedTUNMetrics.descriptorIdentity(fd)==identity {
                    ScopedTUNMetrics.shared.increment("descriptorMatchedAfter")
                }
                #endif
                challenge=nonce
                #if !APL_PROVIDER_FULL_ROUTE_QA
                deadline=Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds:20_000_000_000)
                    guard !Task.isCancelled,let self else{return}
                    self.cancelTunnelWithError(NativeLabError.stage(26).safeNSError)
                }
                #endif
                completionHandler(nil)
            } catch {
                await cleanup()
                completionHandler((error as? NativeLabError)?.safeNSError ?? NativeLabError.stage(27).safeNSError)
            }
        }
    }
    override func handleAppMessage(_ messageData:Data,completionHandler:((Data?)->Void)?) {
        Task { @MainActor in
            #if APL_PROVIDER_SCOPED_TUN_QA
            if messageData==Data("apl-lab-counters-v1".utf8),consumed {
                completionHandler?(try? JSONSerialization.data(withJSONObject:ScopedTUNMetrics.shared.snapshot(),options:.sortedKeys))
                return
            }
            #endif
            guard messageData==Data("apl-provider-direct-v1".utf8),started,!consumed,let nonce=challenge else {
                completionHandler?(nil);return
            }
            consumed=true;challenge=nil
            #if APL_PROVIDER_SCOPED_TUN_QA
            // The host made the request through the /32 route; this message
            // only obtains native teardown evidence. No second direct probe.
            _=nonce
            let result=["rustDrainConfirmed":await drainRust()]
            if metricsStarted {ScopedTUNMetrics.shared.stop();metricsStarted=false}
            #else
            let result=await Task.detached(priority:.userInitiated){ProviderSOCKSProbe.run(nonce)}.value
            #endif
            var report=result
            let stopReply=NativeLabRuntime.call("stopXray")
            let stopped=stopReply != nil && NativeLabRuntime.running==false
            started = !stopped
            report["nativeStopConfirmed"]=stopped
            report["providerProcess"]=true
            #if APL_PROVIDER_FULL_ROUTE_QA
            report["scopedRouteOnly"]=false
            report["fullRouteSyntheticGuard"]=true
            #else
            report["scopedRouteOnly"]=true
            #endif
            #if APL_PROVIDER_SCOPED_TUN_QA
            report["rustTUNStarted"]=true
            #else
            report["rustTUNStarted"]=false
            #endif
            report["releaseAuthorized"]=false
            completionHandler?(try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys))
        }
    }
    override func stopTunnel(with reason:NEProviderStopReason,completionHandler:@escaping()->Void) {
        Task { @MainActor in await cleanup();completionHandler() }
    }
    #if APL_PROVIDER_SCOPED_TUN_QA
    @MainActor private func drainRust() async -> Bool {
        exitGate.invalidate()
        guard rustStarted else{return true}
        do {
            try await TunnelEngineHandoff.stopAndDrain(engineQueue:engineQueue,timeout:5){_=tun2proxy_stop()}
            rustStarted=false
            return true
        } catch {return false}
    }
    #endif
    @MainActor private func cleanup() async {
        consumed=true;challenge=nil;deadline?.cancel();deadline=nil
        #if APL_PROVIDER_SCOPED_TUN_QA
        _=await drainRust()
        if metricsStarted {ScopedTUNMetrics.shared.stop();metricsStarted=false}
        #endif
        if started {
            _=NativeLabRuntime.call("stopXray")
            started=false
        }
        try? await setTunnelNetworkSettings(nil)
    }
}

private struct ProviderReceipt { var stage="notStarted";var greeting=false;var connect=false;var httpReceipt=false }
private enum ProviderSOCKSProbe {
    static func run(_ nonce:String)->[String:Bool] {
        var receipt=ProviderReceipt();probe(nonce,&receipt)
        return ["socksGreeting":receipt.greeting,"socksConnect":receipt.connect,"exactHTTPReceipt":receipt.httpReceipt]
    }
    static func sendAll(_ fd:Int32,_ data:[UInt8])->Bool {
        var offset=0
        while offset<data.count {
            let sent=data.withUnsafeBytes {Darwin.send(fd,$0.baseAddress!.advanced(by:offset),data.count-offset,0)}
            guard sent>0 else{return false}
            offset+=sent
        }
        return true
    }
    static func exact(_ fd:Int32,_ count:Int)->[UInt8]? {
        var data=[UInt8](repeating:0,count:count),offset=0
        while offset<count {
            let got=data.withUnsafeMutableBytes {Darwin.recv(fd,$0.baseAddress!.advanced(by:offset),count-offset,0)}
            guard got>0 else{return nil}
            offset+=got
        }
        return data
    }
    static func contains(_ haystack:[UInt8],_ needle:[UInt8])->Bool {
        guard haystack.count>=needle.count,!needle.isEmpty else{return false}
        return (0...(haystack.count-needle.count)).contains { haystack[$0..<($0+needle.count)].elementsEqual(needle) }
    }
    #if APL_PROVIDER_SCOPED_TUN_QA
    static func greetingOnly()->Bool {
        let fd=Darwin.socket(AF_INET,SOCK_STREAM,0)
        guard fd>=0 else{return false}
        defer{Darwin.close(fd)}
        var timeout=timeval(tv_sec:1,tv_usec:0),one:Int32=1
        _=withUnsafePointer(to:&one){setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,$0,socklen_t(MemoryLayout<Int32>.size))}
        _=withUnsafePointer(to:&timeout){setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,$0,socklen_t(MemoryLayout<timeval>.size))}
        _=withUnsafePointer(to:&timeout){setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,$0,socklen_t(MemoryLayout<timeval>.size))}
        var addr=sockaddr_in()
        addr.sin_len=UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family=sa_family_t(AF_INET);addr.sin_port=UInt16(39879).bigEndian
        guard "127.0.0.1".withCString({inet_pton(AF_INET,$0,&addr.sin_addr)})==1 else{return false}
        guard withUnsafePointer(to:&addr,{$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}})==0 else{return false}
        return sendAll(fd,[5,1,0]) && exact(fd,2)==[5,0]
    }
    #endif
    static func probe(_ nonce:String,_ receipt:inout ProviderReceipt) {
        let fd=Darwin.socket(AF_INET,SOCK_STREAM,0)
        guard fd>=0 else{receipt.stage="socketUnavailable";return}
        defer{Darwin.close(fd)}
        var timeout=timeval(tv_sec:3,tv_usec:0)
        var one:Int32=1
        _=withUnsafePointer(to:&one){setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,$0,socklen_t(MemoryLayout<Int32>.size))}
        _=withUnsafePointer(to:&timeout){setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,$0,socklen_t(MemoryLayout<timeval>.size))}
        _=withUnsafePointer(to:&timeout){setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,$0,socklen_t(MemoryLayout<timeval>.size))}
        var addr=sockaddr_in()
        addr.sin_len=UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family=sa_family_t(AF_INET)
        addr.sin_port=UInt16(39879).bigEndian
        guard "127.0.0.1".withCString({inet_pton(AF_INET,$0,&addr.sin_addr)})==1 else{return}
        let connected=withUnsafePointer(to:&addr){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}}
        guard connected==0 else{receipt.stage="socksUnavailable";return}
        guard sendAll(fd,[5,1,0]),exact(fd,2)==[5,0] else{receipt.stage="greetingFailed";return}
        receipt.greeting=true
        guard sendAll(fd,[5,1,0,1,198,51,100,77,0x9b,0xcb]),
              let reply=exact(fd,10),reply[0...3].elementsEqual([5,0,0,1]) else{receipt.stage="connectFailed";return}
        receipt.connect=true
        let request=Array("GET /\(nonce) HTTP/1.1\r\nHost: 198.51.100.77\r\nConnection: close\r\n\r\n".utf8)
        guard sendAll(fd,request) else{receipt.stage="httpWriteFailed";return}
        let target=Array("APL_RECEIPT:\(nonce)".utf8)
        var response=[UInt8]()
        while response.count<8192 {
            var bytes=[UInt8](repeating:0,count:2048)
            let n=bytes.withUnsafeMutableBytes{Darwin.recv(fd,$0.baseAddress!,2048,0)}
            if n<=0{break}
            response.append(contentsOf:bytes.prefix(n))
            if let split=Data(response).range(of:Data([13,10,13,10])),
               let header=String(data:Data(response[..<split.lowerBound]),encoding:.utf8),
               (header.hasPrefix("HTTP/1.0 200 ") || header.hasPrefix("HTTP/1.1 200 ")),
               Array(response[split.upperBound...])==target {
                receipt.httpReceipt=true;receipt.stage="httpReceipt";return
            }
        }
        receipt.stage="httpReceiptMissing"
    }
}
