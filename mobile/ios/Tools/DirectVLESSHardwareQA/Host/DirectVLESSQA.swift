// Independent QA-only app; NEVER calls NetworkExtension, Keychain, App Group or profile APIs.
import Darwin
import Foundation
import Network
import SwiftUI

private struct QAInput: Decodable {
    let runID: UUID
    let nonce: String
    let link: String
    static func consume(_ url: URL) -> Self? {
        defer { try? FileManager.default.removeItem(at:url) }
        guard let data=try? Data(contentsOf:url),data.count<=4608,
              let root=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              Set(root.keys)==Set(["runID","nonce","link"]),
              let input=try? JSONDecoder().decode(Self.self,from:data),
              input.nonce.utf8.count==40,
              input.nonce.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),
              let candidate=try? VLESSRealityShareLink.parse(input.link),
              candidate.serverHost=="192.168.1.80",candidate.serverPort==39882,
              candidate.serverName=="example.com" else{return nil}
        return input
    }
}

private struct QAReceipt {
    let runID:String
    var stage="notStarted"
    #if APL_DIRECT_PRODUCT_GO_QA
    let engineVariant="unifiedGoProductBoundUDP"
    #else
    let engineVariant="standaloneTCP"
    #endif
    var greeting=false
    var connect=false
    var httpReceipt=false
    var stopped=false
    var directLANReachable=false
    var lanErrorCode:Int32=0
    var lanPhase="notProbed"
    var lanPermissionDenied=false
    var wifiHasIPv4=false
    var wifiOnTestSubnet=false
    func encoded()->Data? {
        try? JSONSerialization.data(withJSONObject:[
            "schema":1,"runID":runID,"stage":stage,"engineVariant":engineVariant,"socksGreeting":greeting,
            "socksConnect":connect,"exactHTTPReceipt":httpReceipt,
            "xrayStopConfirmed":stopped,"directLANReachable":directLANReachable,
            "lanErrorCode":lanErrorCode,"lanPhase":lanPhase,
            "lanPermissionDenied":lanPermissionDenied,"wifiHasIPv4":wifiHasIPv4,
            "wifiOnTestSubnet":wifiOnTestSubnet,"networkExtensionUsed":false,
            "profilesAccessed":false,"releaseAuthorized":false],options:[.sortedKeys])
    }
}

// A bounded TCP-only transport control BEFORE libXray. Sends no application
// payload, uses the same private-LAN peer socket, and never reads user routes.
private struct LANProbe {
    let connected:Bool
    let errorCode:Int32
    let phase:String
    let wifiHasIPv4:Bool
    let wifiOnTestSubnet:Bool
}

private enum DirectLANControl {
    private static func wifiFlags() -> (Bool,Bool) {
        var head:UnsafeMutablePointer<ifaddrs>?
        guard Darwin.getifaddrs(&head)==0,let root=head else{return (false,false)}
        defer { Darwin.freeifaddrs(root) }
        var item:UnsafeMutablePointer<ifaddrs>?=root
        var hasIPv4=false,onTestSubnet=false
        while let entry=item {
            defer { item=entry.pointee.ifa_next }
            guard String(cString:entry.pointee.ifa_name)=="en0",
                  let raw=entry.pointee.ifa_addr,
                  Int32(raw.pointee.sa_family)==AF_INET else{continue}
            hasIPv4=true
            let addr=raw.withMemoryRebound(to:sockaddr_in.self,capacity:1){$0.pointee}
            if UInt32(bigEndian:addr.sin_addr.s_addr) & 0xffffff00 == 0xc0a80100 {
                onTestSubnet=true
            }
        }
        return (hasIPv4,onTestSubnet)
    }

    static func probe() -> LANProbe {
        let (wifiIPv4,sameSubnet)=wifiFlags()
        func result(_ connected:Bool,_ code:Int32,_ phase:String)->LANProbe {
            LANProbe(connected:connected,errorCode:code,phase:phase,
                     wifiHasIPv4:wifiIPv4,wifiOnTestSubnet:sameSubnet)
        }
        let fd=Darwin.socket(AF_INET,SOCK_STREAM,0)
        guard fd>=0 else{return result(false,errno,"socket")}
        defer {Darwin.close(fd)}
        let flags=Darwin.fcntl(fd,F_GETFL)
        guard flags>=0,Darwin.fcntl(fd,F_SETFL,flags|O_NONBLOCK)==0 else {
            return result(false,errno,"nonblocking")
        }
        var addr=sockaddr_in()
        addr.sin_len=UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family=sa_family_t(AF_INET)
        addr.sin_port=UInt16(39882).bigEndian
        guard "192.168.1.80".withCString({inet_pton(AF_INET,$0,&addr.sin_addr)})==1 else {
            return result(false,0,"invalidTarget")
        }
        let connected=withUnsafePointer(to:&addr) {
            $0.withMemoryRebound(to:sockaddr.self,capacity:1) {
                Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected==0{return result(true,0,"connected")}
        let connectError=errno
        guard connectError==EINPROGRESS else{return result(false,connectError,"connect")}
        var ready=pollfd(fd:fd,events:Int16(POLLOUT),revents:0)
        let polled=Darwin.poll(&ready,1,2500)
        if polled==0{return result(false,0,"timeout")}
        if polled<0{return result(false,errno,"poll")}
        var soError:Int32=0
        var size=socklen_t(MemoryLayout<Int32>.size)
        guard withUnsafeMutablePointer(to:&soError,{
            getsockopt(fd,SOL_SOCKET,SO_ERROR,$0,&size)
        })==0 else{return result(false,errno,"getsockopt")}
        return result(soError==0,soError,soError==0 ? "connected" : "socketError")
    }
}

// Apple's TN3179 recommends checking an endpoint-specific NWConnection
// currentPath.unsatisfiedReason for .localNetworkDenied. This is a QA-only
// outbound TCP attempt; no payload, VPN management, IP/profile logging.
private struct LANPrivacyResult {
    let state:String
    let localNetworkDenied:Bool
}

private enum LANPrivacyControl {
    static func probe() -> LANPrivacyResult {
        let connection=NWConnection(host:"192.168.1.80",port:39882,using:.tcp)
        let semaphore=DispatchSemaphore(value:0)
        let lock=NSLock()
        var state="timeout"
        var localDenied=false
        connection.stateUpdateHandler={ newState in
            let label:String
            switch newState {
            case .ready: label="ready"
            case .waiting(_): label="waiting"
            case .failed(_): label="failed"
            default: return
            }
            lock.lock()
            state=label
            localDenied=(connection.currentPath?.unsatisfiedReason == .localNetworkDenied)
            lock.unlock()
            semaphore.signal()
        }
        connection.start(queue:DispatchQueue.global(qos:.utility))
        _=semaphore.wait(timeout: .now() + .seconds(3))
        lock.lock()
        let result=LANPrivacyResult(state:state,localNetworkDenied:localDenied)
        lock.unlock()
        connection.stateUpdateHandler=nil
        connection.cancel()
        return result
    }
}

private enum SOCKSReceipt {
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
    static func run(_ nonce:String,_ receipt:inout QAReceipt) {
        let fd=Darwin.socket(AF_INET,SOCK_STREAM,0)
        guard fd>=0 else{receipt.stage="socketUnavailable";return}
        defer{Darwin.close(fd)}
        var timeout=timeval(tv_sec:5,tv_usec:0)
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
            if contains(response,target){receipt.httpReceipt=true;receipt.stage="httpReceipt";return}
        }
        receipt.stage="httpReceiptMissing"
    }
}

private enum DirectQAEngine {
    static func run(_ input:QAInput)->QAReceipt {
        var receipt=QAReceipt(runID:input.runID.uuidString.lowercased())
        guard let profile=try? VLESSRealityShareLink.parse(input.link),
              profile.serverHost=="192.168.1.80",profile.serverPort==39882,
              profile.serverName=="example.com" else{receipt.stage="rejectedInput";return receipt}
        guard NativeLabRuntime.running==false else{receipt.stage="alreadyRunning";return receipt}
        let lan=DirectLANControl.probe()
        receipt.directLANReachable=lan.connected
        receipt.lanErrorCode=lan.errorCode
        receipt.lanPhase=lan.phase
        receipt.wifiHasIPv4=lan.wifiHasIPv4
        receipt.wifiOnTestSubnet=lan.wifiOnTestSubnet
        if !lan.connected {
            let privacy=LANPrivacyControl.probe()
            receipt.lanPermissionDenied=privacy.localNetworkDenied
            receipt.stage=privacy.localNetworkDenied ? "localNetworkPermissionDenied" : "lanUnavailable"
            receipt.stopped=(NativeLabRuntime.running==false)
            return receipt // Never start Xray against an unreachable LAN peer.
        }
        do {
            #if APL_DIRECT_PRODUCT_GO_QA
            // Exact product compiler and underlay transformation; no OS tunnel.
            guard lan.wifiOnTestSubnet,if_nametoindex("en0") != 0,
                  (NativeLabRuntime.call("xrayVersion")?["data"] as? [String:Any])?["version"] as? String == "26.11.9" else {
                receipt.stage="productUnderlayUnavailable";return receipt
            }
            let raw=try XrayVLESSRuntimeConfig.compileValidatedCandidate(profile,socksPort:39879,datagramReview:true)
            let bound=try XrayVLESSRuntimeConfig.bindPhysicalUnderlay(raw,interfaceName:"en0",expectedAddress:"192.168.1.80",expectedPort:39882)
            guard let config=String(data:bound,encoding:.utf8),
                  NativeLabRuntime.call("testXray",config:config) != nil,
                  NativeLabRuntime.running==false else {
                receipt.stage="productConfigRejected";return receipt
            }
            #else
            let config=try NativeLabRuntime.prepare(profile,port:39879)
            #endif
            receipt.stage="verifiedConfig"
            // Explicit stop before returning the value: a defer could update a
            // local copy only after Swift evaluates the returned struct.
            let started=NativeLabRuntime.call("runXray",config:config) != nil
            if started && NativeLabRuntime.running==true {
                receipt.stage="nativeStarted"
                SOCKSReceipt.run(input.nonce,&receipt)
            } else { receipt.stage="startFailed" }
            // Native start can be ambiguous: always attempt one controlled stop.
            _=NativeLabRuntime.call("stopXray")
            receipt.stopped=(NativeLabRuntime.running==false)
        } catch {receipt.stage="configRejected"}
        return receipt
    }
}

@MainActor private final class QAState:ObservableObject {
    @Published var status="Not requested"
    private var used=false
    func start() async {
        let args=ProcessInfo.processInfo.arguments
        let lanOnly=args.contains("--apl-vless-lan-probe")
        let full=args.contains("--apl-vless-direct-qa")
        guard !used,lanOnly != full else{return}
        used=true
        let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        if lanOnly {
            status="Testing private LAN TCP only"
            let evidence=await Task.detached(priority:.userInitiated) {
                (DirectLANControl.probe(),LANPrivacyControl.probe())
            }.value
            let result=evidence.0
            let privacy=evidence.1
            let report:[String:Any]=[
                "schema":1,"runID":UUID().uuidString.lowercased(),
                "directLANReachable":result.connected,"lanErrorCode":result.errorCode,
                "lanPhase":result.phase,"wifiHasIPv4":result.wifiHasIPv4,
                "wifiOnTestSubnet":result.wifiOnTestSubnet,
                "nwConnectionState":privacy.state,
                "nwLocalNetworkDenied":privacy.localNetworkDenied,
                "xrayWasNotStarted":true,"networkExtensionUsed":false,
                "profilesAccessed":false,"releaseAuthorized":false]
            if let bytes=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]) {
                try? bytes.write(to:dir.appendingPathComponent("apl-vless-lan-control-result.json"),
                                 options:[.atomic,.completeFileProtection])
            }
            status=privacy.localNetworkDenied ? "Allow Local Network in iOS Settings" :
                   (result.connected ? "Private LAN TCP verified" : "Private LAN TCP unavailable")
            return
        }
        guard let input=QAInput.consume(dir.appendingPathComponent("apl-vless-direct-input.json")) else{
            status="Synthetic input rejected";return
        }
        status="Checking isolated Xray"
        let receipt=await Task.detached(priority:.userInitiated) {DirectQAEngine.run(input)}.value
        if let bytes=receipt.encoded() {
            try? bytes.write(to:dir.appendingPathComponent("apl-vless-direct-result.json"),options:[.atomic,.completeFileProtection])
        }
        status=receipt.httpReceipt && receipt.stopped ? "Receipt verified" : "Not accepted: \(receipt.stage)"
    }
}

@main private struct DirectXrayApp:App {
    @StateObject private var state=QAState()
    var body:some Scene {
        WindowGroup {
            VStack(spacing:16){Text("APL direct Xray QA");Text(state.status)}.task{await state.start()}
        }
    }
}
