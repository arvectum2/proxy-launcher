// Isolated full-route QA only. Blackhole is first/default; only the fixed
// synthetic witness tuple may reach the disposable VLESS peer.
import Foundation

enum FullRouteGuard {
    enum Failure:Error {case invalidInput}
    static func restrict(_ bound:Data,kind:FixedWitnessKind = .tcp4)throws->Data {
        guard var root=try JSONSerialization.jsonObject(with:bound) as? [String:Any],
              Set(root.keys)==Set(["inbounds","outbounds","routing","log"]),
              let inbound=root["inbounds"] as? [[String:Any]],inbound.count==1,
              inbound[0]["tag"] as? String=="apl-local",
              inbound[0]["listen"] as? String=="127.0.0.1",
              inbound[0]["port"] as? Int==39879,
              inbound[0]["protocol"] as? String=="socks",
              let outbound=root["outbounds"] as? [[String:Any]],outbound.count==1,
              outbound[0]["tag"] as? String=="apl-vless",
              outbound[0]["protocol"] as? String=="vless",
              let endpoint=outbound[0]["settings"] as? [String:Any],
              endpoint["address"] as? String=="192.168.1.80",
              endpoint["port"] as? Int==39882,
              let stream=outbound[0]["streamSettings"] as? [String:Any],
              let socket=stream["sockopt"] as? [String:Any],
              socket["interface"] as? String=="en0" else {throw Failure.invalidInput}
        let deny:[String:Any]=["tag":"qa-drop","protocol":"blackhole","settings":[:]]
        root["outbounds"]=[deny,outbound[0]]
        root["routing"]=["domainStrategy":"AsIs","rules":[
            ["type":"field","inboundTag":["apl-local"],"network":kind.network,
             "ip":[kind.cidr],"port":String(kind.port),"outboundTag":"apl-vless"],
            ["type":"field","network":"tcp,udp","outboundTag":"qa-drop"]
        ]]
        root["log"]=["loglevel":"none"]
        return try JSONSerialization.data(withJSONObject:root,options:[.sortedKeys])
    }
}
