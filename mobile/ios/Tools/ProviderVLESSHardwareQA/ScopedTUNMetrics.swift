// QA only. Report finite counters, never raw logs or packet contents.
import Foundation
#if APL_PROVIDER_SCOPED_TUN_QA
import Darwin
import tun2proxy

final class ScopedTUNMetrics: @unchecked Sendable {
    static let shared=ScopedTUNMetrics()
    private let lock=NSLock()
    private var values:[String:Int]=[:]
    private var collecting=false

    func start() {
        lock.lock();values=[:];collecting=true;lock.unlock()
        tun2proxy_set_log_callback({ _, message, _ in
            guard let message else{return}
            ScopedTUNMetrics.shared.classify(String(cString:message))
        },nil)
        tun2proxy_set_traffic_status_callback(1,{ status,_ in
            guard let status else{return}
            ScopedTUNMetrics.shared.traffic(tx:status.pointee.tx,rx:status.pointee.rx)
        },nil)
        tun2proxy_set_flow_event_callback({ host,_,event,_ in
            guard let host,String(cString:host)=="198.51.100.77",(0...7).contains(event) else{return}
            ScopedTUNMetrics.shared.increment("targetFlow"+String(event))
        },nil)
    }
    func stop() {
        lock.lock();collecting=false;lock.unlock()
        tun2proxy_set_log_callback(nil,nil)
        tun2proxy_set_traffic_status_callback(1,nil,nil)
        tun2proxy_set_flow_event_callback(nil,nil)
    }
    func snapshot()->[String:Int] {
        lock.lock();defer{lock.unlock()};return values
    }
    func increment(_ key:String) {
        lock.lock();defer{lock.unlock()}
        guard collecting else{return}
        values[key]=min(1_000_000,(values[key] ?? 0)+1)
    }
    private func classify(_ message:String) {
        let line=message.lowercased()
        increment("logCallbacks")
        for (needle,key) in [("tcp","tcpLog"),("socks","socksLog"),("connect","connectLog"),
                              ("198.51.100.77","targetLog"),("error","errorLog"),("failed","failedLog"),
                              ("permission denied","permissionLog"),("timed out","timeoutLog"),
                              ("connection refused","refusedLog"),("network is unreachable","unreachableLog")] {
            if line.contains(needle){increment(key)}
        }
    }
    private func traffic(tx:UInt64,rx:UInt64) {
        lock.lock();defer{lock.unlock()}
        guard collecting else{return}
        values["trafficCallbacks"]=min(1_000_000,(values["trafficCallbacks"] ?? 0)+1)
        // Maximum reported value, not sum of potentially cumulative samples.
        values["maxReportedTX"]=max(values["maxReportedTX"] ?? 0,Int(min(tx,1_000_000_000)))
        values["maxReportedRX"]=max(values["maxReportedRX"] ?? 0,Int(min(rx,1_000_000_000)))
    }
    static func descriptorIdentity(_ fd:Int32)->String? {
        guard fcntl(fd,F_GETFD)>=0 else{return nil}
        var value=[CChar](repeating:0,count:Int(IFNAMSIZ))
        var len=socklen_t(value.count)
        guard value.withUnsafeMutableBytes({getsockopt(fd,2,2,$0.baseAddress,&len)})==0,
              len>0,len<=socklen_t(value.count),value.contains(0) else{return nil}
        let name=String(cString:value)
        return name.hasPrefix("utun") ? name:nil
    }
}
#endif
