import Foundation

/// Offline opt-in policy. A due hint is not a request or a scheduler.
/// No token, URL, network API, persistence, or automatic profile mutation.
@MainActor final class ProxySubscriptionRefreshReview {
    enum Failure: Error {case invalidPolicy, busy, staleReview, invalidBody, expired, conflictingRows}
    enum Interval: TimeInterval {case hourly=3600, daily=86400, weekly=604800}
    struct Source: Equatable {let id:UUID;let revision:UUID}
    struct Request: Equatable {
        let source:Source
        let defaultType:ProxyType
        fileprivate let nonce:UUID
        fileprivate let started:TimeInterval
    }
    struct Summary: Equatable {
        let request:Request
        let received:Int
        let existing:Int
        let repeated:Int
        let additions:Int
    }
    private struct Endpoint: Hashable {
        let type:ProxyType;let host:String;let port:Int;let username:String
        init(_ item:ImportedProxy){type=item.type;host=item.host.lowercased();port=item.port;username=item.username}
        init(_ item:ProxyProfile){type=item.type;host=item.host.lowercased();port=item.port;username=item.username ?? ""}
    }
    private struct Pending: CustomStringConvertible, CustomReflectable {
        let summary:Summary;let baseline:[ProxyProfile];let additions:[ImportedProxy];let at:TimeInterval
        var description:String {"SubscriptionRefreshPending(redacted)"}
        var customMirror:Mirror {Mirror(self,children:[:])}
    }
    private let elapsed:()->TimeInterval
    private var consent:(source:Source,interval:Interval)?
    private var lastAttempt:TimeInterval?
    private var request:Request?
    private var pending:Pending?
    static let maxExisting=2048
    static let reviewLifetime:TimeInterval=300
    static let responseLifetime:TimeInterval=60
    init(elapsed:@escaping ()->TimeInterval={ProcessInfo.processInfo.systemUptime}){self.elapsed=elapsed}

    /// Consent is memory-only and scoped to the exact saved source revision.
    /// Re-enabling starts a fresh delay; cancellation invalidates old work.
    func optIn(_ source:Source,interval:Interval) throws {
        let now=elapsed();guard now.isFinite,now>=0 else{throw Failure.invalidPolicy}
        cancel();consent=(source,interval);lastAttempt=now
    }
    func optOut(){cancel();consent=nil;lastAttempt=nil}
    func cancel(){request=nil;pending=nil}
    func isDue(_ source:Source,foreground:Bool)->Bool {
        guard foreground,request==nil,pending==nil,let consent,consent.source==source,let lastAttempt else{return false}
        let age=elapsed()-lastAttempt
        return age.isFinite && age>=consent.interval.rawValue
    }
    /// Manual user action remains possible independently of opt-in. An
    /// optional due hint cannot start a download by itself.
    func begin(_ source:Source,defaultType:ProxyType,foreground:Bool,userInitiated:Bool) throws -> Request {
        guard foreground,userInitiated,defaultType != .auto else{throw Failure.invalidPolicy}
        guard request==nil,pending==nil else{throw Failure.busy}
        let now=elapsed();guard now.isFinite,now>=0 else{throw Failure.invalidPolicy}
        if consent?.source==source {lastAttempt=now}
        let r=Request(source:source,defaultType:defaultType,nonce:UUID(),started:now);request=r;return r
    }
    /// Receive only already user-authorized bytes. No replacement/deletion;
    /// duplicates with inconsistent credentials in the same response fail.
    func review(_ bytes:Data,for r:Request,currentSource:Source,existing:[ProxyProfile],foreground:Bool) throws -> Summary {
        guard request==r else{throw Failure.staleReview}
        request=nil;pending=nil
        let age=elapsed()-r.started
        guard age.isFinite,age>=0,age<Self.responseLifetime else{throw Failure.expired}
        guard foreground,currentSource==r.source,existing.count<=Self.maxExisting,Set(existing.map(\.id)).count==existing.count else{throw Failure.staleReview}
        let decoded=try ProxySubscriptionImport.decode(bytes,defaultType:r.defaultType)
        let items=try ProxyImport.parse(decoded,defaultType:r.defaultType)
        let seen=Set(existing.map(Endpoint.init));var unique:[Endpoint:ImportedProxy]=[:];var additions:[ImportedProxy]=[];var repeated=0;var already=0
        for item in items {
            let key=Endpoint(item)
            if let old=unique[key] {
                guard old.password==item.password else{throw Failure.conflictingRows}
                repeated+=1;continue
            }
            unique[key]=item
            if seen.contains(key){already+=1}else{additions.append(item)}
        }
        let now=elapsed();guard now.isFinite,now>=0 else{throw Failure.invalidPolicy}
        let s=Summary(request:r,received:items.count,existing:already,repeated:repeated,additions:additions.count)
        // Existing identities with changed passwords are deliberately skipped;
        // these metadata do not contain the existing Keychain secret.
        pending=Pending(summary:s,baseline:existing,additions:additions,at:now);return s
    }
    /// Returns additive candidates only after explicit single-use approval.
    /// The caller owns the real import transaction and must recheck at commit.
    func confirm(_ summary:Summary,currentSource:Source,existing:[ProxyProfile],foreground:Bool) throws -> [ImportedProxy] {
        guard let p=pending,p.summary==summary else{throw Failure.staleReview}
        pending=nil
        let age=elapsed()-p.at
        guard age.isFinite,age>=0,age<Self.reviewLifetime else{throw Failure.expired}
        guard foreground,currentSource==summary.request.source,existing==p.baseline else{throw Failure.staleReview}
        return p.additions
    }
}
