// Independent QA-only app; NEVER calls NetworkExtension, Keychain, App Group or profile APIs.
import Darwin
import Foundation
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
    var greeting=false
    var connect=false
    var httpReceipt=false
    var stopped=false
    var directLANReachable=false
    func encoded()->Data? {
        try? JSONSerialization.data(withJSONObject:[
            "schema":1,"runID":runID,"stage":stage,"socksGreeting":greeting,
            "socksConnect":connect,"exactHTTPReceipt":httpReceipt,
            "xrayStopConfirmed":stopped,"directLANReachable":directLANReachable,"networkExtensionUsed":false,
            "profilesAccessed":false,"releaseAuthorized":false],options:[.sortedKeys])
    }
}

// A bounded TCP-only transport control BEFORE libXray. Sends no application
// payload, uses the same private-LAN peer socket, and never reads user routes.
private enum DirectLANControl {
    static func canConnect() -> Bool {
        let fd=Darwin.socket(AF_INET,SOCK_STREAM,0)
        guard fd>=0 else{return false}
        defer{Darwin.close(fd)}
        let flags=Darwin.fcntl(fd,F_GETFL)
        guard flags>=0,Darwin.fcntl(fd,F_SETFL,flags|O_NONBLOCK)==0 else{return false}
        var addr=sockaddr_in()
        addr.sin_len=UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family=sa_family_t(AF_INET)
        addr.sin_port=UInt16(39882).bigEndian
        guard "192.168.1.80".withCString({inet_pton(AF_INET,$0,&addr.sin_addr)})==1 else{return false}
        let connected=withUnsafePointer(to:&addr) {
            $0.withMemoryRebound(to:sockaddr.self,capacity:1) {
                Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected==0{return true}
        guard errno==EINPROGRESS else{return false}
        var ready=pollfd(fd:fd,events:Int16(POLLOUT),revents:0)
        guard Darwin.poll(&ready,1,2500)>0,ready.revents & Int16(POLLOUT) != 0 else{return false}
        var soError:Int32=0
        var size=socklen_t(MemoryLayout<Int32>.size)
        guard withUnsafeMutablePointer(to:&soError,{
            getsockopt(fd,SOL_SOCKET,SO_ERROR,$0,&size)
        })==0 else{return false}
        return soError==0
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
        receipt.directLANReachable=DirectLANControl.canConnect()
        do {
            let config=try NativeLabRuntime.prepare(profile,port:39879)
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
        guard !used,ProcessInfo.processInfo.arguments.contains("--apl-vless-direct-qa") else{return}
        used=true
        let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
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
