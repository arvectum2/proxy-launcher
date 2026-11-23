import SwiftUI
import Network
import Foundation

@MainActor final class QAUDPProbe: ObservableObject {
    @Published var status = "Not authorized"
    private var used = false
    private struct Input: Decodable {
        let runID: UUID
        let nonce: String
    }
    private final class Once: @unchecked Sendable {
        private let lock=NSLock()
        private var finish: ((Data?)->Void)?
        init(_ finish:@escaping(Data?)->Void){self.finish=finish}
        func send(_ value:Data?){
            lock.lock();let f=finish;finish=nil;lock.unlock()
            f?(value)
        }
    }
    private func probe(_ host:String, request:Data) async -> Bool {
        let connection=NWConnection(host:NWEndpoint.Host(host),port:39883,using:.udp)
        let response:Data?=await withCheckedContinuation { (continuation:CheckedContinuation<Data?,Never>) in
            let once=Once{continuation.resume(returning:$0)}
            let queue=DispatchQueue(label:"apl.udp.qa.once")
            connection.stateUpdateHandler={state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler=nil
                    connection.send(content:request,completion:.contentProcessed{error in
                        guard error == nil else {once.send(nil);return}
                        connection.receiveMessage{data,_,_,error in once.send(error == nil ? data : nil)}
                    })
                case .failed,.cancelled:once.send(nil)
                default:break
                }
            }
            queue.asyncAfter(deadline:.now()+6){once.send(nil);connection.cancel()}
            connection.start(queue:queue)
        }
        connection.cancel()
        return response == Data("APL_RECEIPT:".utf8) + Data(request.dropFirst("APL_UDP:".utf8.count))
    }
    private func tcp4Control(_ nonce:String) async -> Bool {
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=5
        config.timeoutIntervalForResource=6
        config.connectionProxyDictionary=[:]
        config.urlCache=nil
        config.httpCookieStorage=nil
        let session=URLSession(configuration:config)
        defer {session.invalidateAndCancel()}
        guard let url=URL(string:"http://198.51.100.77:39883/"+nonce) else{return false}
        do {
            let (data,response)=try await session.data(from:url)
            return (response as? HTTPURLResponse)?.statusCode==200 && data==Data(("APL_RECEIPT:"+nonce).utf8)
        } catch {return false}
    }
    func runIfAuthorized() async {
        guard !used,ProcessInfo.processInfo.arguments.contains("--apl-product-udp-only") else {return}
        used=true
        let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let input=docs.appendingPathComponent("apl-standalone-udp-input.json")
        let output=docs.appendingPathComponent("apl-standalone-udp-result.json")
        guard let data=try? Data(contentsOf:input),data.count<512,
              let value=try? JSONDecoder().decode(Input.self,from:data),
              value.nonce.utf8.count==40,
              value.nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {status="Invalid QA input";return}
        try? FileManager.default.removeItem(at:input)
        try? FileManager.default.removeItem(at:output)
        let request=Data(("APL_UDP:"+value.nonce).utf8)
        status="TCP4 control"
        let tcp4=await tcp4Control(value.nonce)
        status="UDP4 probe"
        let v4=await probe("198.51.100.77",request:request)
        status="UDP6 probe"
        let v6=await probe("2001:db8:77::77",request:request)
        let result:[String:Any]=["schema":1,"runID":value.runID.uuidString.lowercased(),"tcp4Control":tcp4,"udp4Reply":v4,"udp6Reply":v6,
                                "osVpnNotTouched":true,"managerNotTouched":true]
        if let bytes=try? JSONSerialization.data(withJSONObject:result,options:.sortedKeys){
            try? bytes.write(to:output,options:.atomic)
        }
        status="Probe complete TCP4 \(tcp4) UDP4 \(v4) UDP6 \(v6)"
    }
}
@main struct APLUDPQAHostApp:App {
    @StateObject private var probe=QAUDPProbe()
    var body:some Scene {
        WindowGroup {
            VStack {
                Text("APL synthetic UDP-only device QA")
                Text(probe.status)
            }.task{await probe.runIfAuthorized()}
        }
    }
}
