import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProxySubscriptionRefreshReviewTests:XCTestCase {
    @MainActor func testOptInOnlyHintsAndNoImplicitRequest() async throws {
        var clock=100.0;let s=ProxySubscriptionRefreshReview(elapsed:{clock}),source=ProxySubscriptionRefreshReview.Source(id:UUID(),revision:UUID())
        XCTAssertFalse(s.isDue(source,foreground:true));try s.optIn(source,interval:.hourly)
        clock+=3599;XCTAssertFalse(s.isDue(source,foreground:true));clock+=1
        XCTAssertTrue(s.isDue(source,foreground:true));XCTAssertFalse(s.isDue(source,foreground:false))
        let changed=ProxySubscriptionRefreshReview.Source(id:source.id,revision:UUID());XCTAssertFalse(s.isDue(changed,foreground:true))
        XCTAssertThrowsError(try s.begin(source,defaultType:.http,foreground:true,userInitiated:false))
        XCTAssertThrowsError(try s.begin(source,defaultType:.http,foreground:false,userInitiated:true))
        let r=try s.begin(source,defaultType:.http,foreground:true,userInitiated:true);XCTAssertFalse(s.isDue(source,foreground:true))
        s.optOut();XCTAssertThrowsError(try s.review(Data("one.example.com:80".utf8),for:r,currentSource:source,existing:[],foreground:true))
        clock+=7200;XCTAssertFalse(s.isDue(source,foreground:true))
    }
    @MainActor func testAdditiveReviewCountsAndSingleUseConfirmation() async throws {
        let s=ProxySubscriptionRefreshReview(),source=ProxySubscriptionRefreshReview.Source(id:UUID(),revision:UUID())
        let old=[ProxyProfile(name:"Existing",host:"one.example.com",port:80,type:.http,username:"bob")]
        let r=try s.begin(source,defaultType:.http,foreground:true,userInitiated:true)
        let data=Data("http://bob:new@one.example.com:80\nsocks5://alice:secret@two.example.com:1080\nsocks5://alice:secret@TWO.example.com:1080".utf8)
        let preview=try s.review(data,for:r,currentSource:source,existing:old,foreground:true)
        XCTAssertEqual(preview.received,3);XCTAssertEqual(preview.existing,1);XCTAssertEqual(preview.repeated,1);XCTAssertEqual(preview.additions,1)
        XCTAssertFalse(String(reflecting:preview).contains("secret"));XCTAssertFalse(String(reflecting:preview).contains("two.example.com"))
        let added=try s.confirm(preview,currentSource:source,existing:old,foreground:true)
        XCTAssertEqual(added.count,1);XCTAssertEqual(added[0].type,.socks5);XCTAssertEqual(added[0].password,"secret")
        XCTAssertThrowsError(try s.confirm(preview,currentSource:source,existing:old,foreground:true))
    }
    @MainActor func testStaleSourceBaselineAndExpiredReview() async throws {
        var clock=100.0;let s=ProxySubscriptionRefreshReview(elapsed:{clock}),source=ProxySubscriptionRefreshReview.Source(id:UUID(),revision:UUID()),next=ProxySubscriptionRefreshReview.Source(id:source.id,revision:UUID())
        let bytes=Data("one.example.com:80".utf8)
        func start() throws -> ProxySubscriptionRefreshReview.Request {try s.begin(source,defaultType:.http,foreground:true,userInitiated:true)}
        let a=try start();XCTAssertThrowsError(try s.review(bytes,for:a,currentSource:next,existing:[],foreground:true))
        let b=try start();clock+=60;XCTAssertThrowsError(try s.review(bytes,for:b,currentSource:source,existing:[],foreground:true))
        let c=try start();let p=try s.review(bytes,for:c,currentSource:source,existing:[],foreground:true)
        XCTAssertThrowsError(try s.confirm(p,currentSource:source,existing:[ProxyProfile(name:"New",host:"other.example.com",port:80,type:.http)],foreground:true))
        let d=try start();let q=try s.review(bytes,for:d,currentSource:source,existing:[],foreground:true);clock+=300
        XCTAssertThrowsError(try s.confirm(q,currentSource:source,existing:[],foreground:true))
        let e=try start();let t=try s.review(bytes,for:e,currentSource:source,existing:[],foreground:true)
        XCTAssertThrowsError(try s.confirm(t,currentSource:source,existing:[],foreground:false))
    }
    @MainActor func testConflictingRowsAndCancellationDoNotYieldAdditions() async throws {
        let s=ProxySubscriptionRefreshReview(),source=ProxySubscriptionRefreshReview.Source(id:UUID(),revision:UUID())
        func start() throws -> ProxySubscriptionRefreshReview.Request {try s.begin(source,defaultType:.http,foreground:true,userInitiated:true)}
        let a=try start();XCTAssertThrowsError(try s.review(Data("http://bob:p1@one.example.com:80\nhttp://bob:p2@one.example.com:80".utf8),for:a,currentSource:source,existing:[],foreground:true))
        let b=try start();XCTAssertThrowsError(try s.review(Data("http://one.example.com:80\nvless://a@other.example.com:443".utf8),for:b,currentSource:source,existing:[],foreground:true))
        let c=try start();s.cancel();let d=try start()
        XCTAssertThrowsError(try s.review(Data("one.example.com:80".utf8),for:c,currentSource:source,existing:[],foreground:true))
        let p=try s.review(Data("one.example.com:80".utf8),for:d,currentSource:source,existing:[],foreground:true)
        s.cancel();XCTAssertThrowsError(try s.confirm(p,currentSource:source,existing:[],foreground:true))
    }
}
