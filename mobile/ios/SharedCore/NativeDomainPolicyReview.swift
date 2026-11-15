import Foundation

/// Read-only inventory of stored intent; never a route authorization.
struct NativeDomainPolicyReview:Equatable {
    enum Source:String {case manual,derivedAlias,legacyOnly,dependency}
    enum Status:String {case configured,approved,pending,rejected,expired,orphaned,suppressed,ambiguous,invalid}
    struct Row:Equatable,Identifiable {
        let host:String
        let parent:String?
        let source:Source
        let status:Status
        var id:String {source.rawValue+"|"+(parent ?? "")+"|"+host}
    }
    let admission:NativeRoutingAdmission
    let rows:[Row]
    let normallyOff:Bool
    var nativeDomainRoutesAvailable:Bool {false}
    enum Failure:Error {case malformed}
    static func inspect(manual:Any?,legacy:Any?,graph:Any?,mode:Any?,at now:Date=Date())throws->Self {
        let admission=NativeRoutingAdmission.inspect(manual:manual,legacy:legacy,graph:graph,mode:mode)
        guard admission != .malformed,now.timeIntervalSince1970.isFinite else{throw Failure.malformed}
        let explicit=try SiteExclusionPolicy.normalizeAll(manual as? [String] ?? [])
        let old=try SiteExclusionPolicy.normalizeAll(legacy as? [String] ?? [])
        let g:SmartExclusionGraph
        if let data=graph as? Data {g=try JSONDecoder().decode(SmartExclusionGraph.self,from:data)}else{g = .init()}
        guard (g.suppressed ?? []).count<=SiteExclusionPolicy.maxEntries*SiteDependencyDiscovery.maxCandidates else{throw Failure.malformed}
        let active=Set(explicit.compactMap(SmartExclusionGraph.root)),manualSet=Set(explicit)
        var rows:[Row]=[]
        func classification(_ h:String)->Status {
            if SiteDependencyDiscovery.isScannableHost(h){return .configured}
            if let p=try? NativeLiteralIPPrefix(h),!h.contains("/"),p.length==(p.isIPv6 ? 128:32){return .configured}
            return .invalid
        }
        for h in explicit {rows.append(.init(host:h,parent:nil,source:.manual,status:classification(h)))}
        for h in explicit.filter(SiteDependencyDiscovery.isScannableHost) {
            for derived in SiteExclusionPolicy.routingHosts(for:h) where !manualSet.contains(derived) {
                rows.append(.init(host:derived,parent:h,source:.derivedAlias,status:classification(derived)))
            }
        }
        let current=Set(try g.effective(manual:explicit,at:now))
        for h in old where !current.contains(h) {rows.append(.init(host:h,parent:nil,source:.legacyOnly,status:classification(h)))}
        let grouped=Dictionary(grouping:g.edges,by: \.id)
        for (_,edges) in grouped.sorted(by:{$0.key<$1.key}) {
            guard let edge=edges.first else{continue}
            let status:Status
            if edges.count != 1 {status = .ambiguous}
            else if (g.suppressed ?? []).contains(edge.id) {status = .suppressed}
            else if SmartExclusionGraph.root(edge.parent) != edge.parent || !SiteDependencyDiscovery.isScannableHost(edge.host) || !(SmartExclusionGraph.validChild(edge.host,for:edge.parent) || (edge.userLinked == true && edge.host != edge.parent && edge.host != "www."+edge.parent)) {status = .invalid}
            else if edge.lastSeen>now || (edge.userLinked != true && now.timeIntervalSince(edge.lastSeen)>=SmartExclusionGraph.ttl) {status = .expired}
            else if !active.contains(edge.parent) {status = .orphaned}
            else {switch edge.decision {case .approved:status = .approved;case .pending:status = .pending;case .rejected:status = .rejected}}
            rows.append(.init(host:edge.host,parent:edge.parent,source:.dependency,status:status))
        }
        for id in Set(g.suppressed ?? []).sorted() where grouped[id]==nil {
            let parts=id.split(separator:"|",omittingEmptySubsequences:false)
            guard parts.count==2,SmartExclusionGraph.root(String(parts[0]))==String(parts[0]),SiteDependencyDiscovery.isScannableHost(String(parts[1])) else{throw Failure.malformed}
            rows.append(.init(host:String(parts[1]),parent:String(parts[0]),source:.dependency,status:.suppressed))
        }
        return .init(admission:admission,rows:rows.sorted{$0.id<$1.id},normallyOff:(mode as? String)=="normallyOff")
    }
}
