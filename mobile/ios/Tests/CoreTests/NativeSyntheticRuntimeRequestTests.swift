import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeSyntheticRuntimeRequestTests:XCTestCase {
    private func input(_ kind:NativeCredentialRecord.Kind)throws -> (UUID,[String:String],[String:NSObject]) {
        let owner=UUID(),binding=NativeCredentialHandoff.Binding(reference:.init(profileID:UUID(),revision:UUID(),kind:kind),session:.init(epoch:UUID(),generation:1,provider:kind.providerName),selectionNonce:UUID())
        let config=NativeSyntheticRuntimeRequest.configuration(owner:owner)
        var opts:[String:NSObject]=config.mapValues{$0 as NSString}
        opts[NativeProviderStartRequest.expectedKey]=try TransportNativeCodec.encode(binding) as NSData
        opts[NativeSyntheticRuntimeRequest.fixtureKey]=(kind == .amneziaWG1 ? Data(repeating:1,count:96):Data("synthetic fixture".utf8)) as NSData
        if kind == .amneziaWG1 {opts[NativeSyntheticRuntimeRequest.localKey]=String(UInt32(0xc0a80122)) as NSString}
        return (owner,config,opts)
    }
    func testSyntheticModesAreDisjointAndRejectReservedCredentialOptions()throws {
        let (owner,config,opts)=try input(.wireGuard)
        let r=try XCTUnwrap(NativeSyntheticRuntimeRequest.inspect(configuration:config,options:opts,provider:.rustXray))
        XCTAssertEqual(r.owner,owner);XCTAssertEqual(Mirror(reflecting:r).children.count,0)
        XCTAssertNil(NativeSyntheticRuntimeRequest.inspect(configuration:config,options:nil,provider:.rustXray))
        XCTAssertNil(NativeSyntheticRuntimeRequest.inspect(configuration:config,options:opts,provider:.standaloneAWG))
        if case .denied=NativeProviderStartRequest.inspect(configuration:config,options:opts,validationEnabled:true){}else{XCTFail("credential path accepted synthetic envelope")}
        var mixed=opts;mixed[NativeProviderStartRequest.ticketKey]=Data([1]) as NSData
        XCTAssertNil(NativeSyntheticRuntimeRequest.inspect(configuration:config,options:mixed,provider:.rustXray))
        mixed=opts;mixed[NativeProviderStartRequest.ownerKey]=UUID().uuidString as NSString
        XCTAssertNil(NativeSyntheticRuntimeRequest.inspect(configuration:config,options:mixed,provider:.rustXray))
        mixed=opts;mixed[NativeSyntheticRuntimeRequest.fixtureKey]=Data(repeating:0,count:4097) as NSData
        XCTAssertNil(NativeSyntheticRuntimeRequest.inspect(configuration:config,options:mixed,provider:.rustXray))
    }
    func testUnifiedSelectorClaimsOnlyOneExactSessionEvenAfterRejectedRequests()throws {
        let (_,x,opts)=try input(.wireGuard),(_,a,aw)=try input(.amneziaWG1)
        var selector=NativeSyntheticEngineSelection()
        XCTAssertNil(selector.claim(configuration:x,options:opts,supported:[.standaloneAWG]))
        XCTAssertNil(selector.claimed)
        let selected=try XCTUnwrap(selector.claim(configuration:a,options:aw,supported:[.rustXray,.standaloneAWG]))
        XCTAssertEqual(selected.binding.reference.kind,.amneziaWG1)
        XCTAssertEqual(selector.claimed,selected.binding.session)
        XCTAssertNil(selector.claim(configuration:x,options:opts,supported:[.rustXray,.standaloneAWG]))
        XCTAssertNil(selector.claim(configuration:a,options:aw,supported:[.rustXray,.standaloneAWG]))
        var second=NativeSyntheticEngineSelection()
        XCTAssertEqual(second.claim(configuration:x,options:opts,supported:[.rustXray,.standaloneAWG])?.binding.reference.kind,.wireGuard)
        XCTAssertNil(second.claim(configuration:a,options:aw,supported:[.rustXray,.standaloneAWG]))
    }
    func testAWGOnlyExactFixtureSizeAndPriorLANAddressScope()throws {
        let (_,config,opts)=try input(.amneziaWG1)
        XCTAssertNotNil(NativeSyntheticRuntimeRequest.inspect(configuration:config,options:opts,provider:.standaloneAWG))
        for invalid in ["0", "3232235856", "3232236031", "2130706433", "3232235776", "03232235810"] {
            var bad=opts;bad[NativeSyntheticRuntimeRequest.localKey]=invalid as NSString
            XCTAssertNil(NativeSyntheticRuntimeRequest.inspect(configuration:config,options:bad,provider:.standaloneAWG),invalid)
        }
        var bad=opts;bad[NativeSyntheticRuntimeRequest.fixtureKey]=Data(repeating:1,count:95) as NSData
        XCTAssertNil(NativeSyntheticRuntimeRequest.inspect(configuration:config,options:bad,provider:.standaloneAWG))
    }
    func testSplitCaseRequiresSeparateGateAndExactAWGEnvelope()throws {
        let (_,a,aw)=try input(.amneziaWG1),(_,w,wg)=try input(.wireGuard)
        for mode in ["included","excluded"] {
            var opts=aw;opts[NativeSyntheticRuntimeRequest.splitKey]=mode as NSString
            XCTAssertNil(NativeSyntheticRuntimeRequest.inspect(configuration:a,options:opts,provider:.standaloneAWG))
            XCTAssertEqual(NativeSyntheticRuntimeRequest.inspect(configuration:a,options:opts,provider:.standaloneAWG,allowSplitRoute:true)?.splitCase?.rawValue,mode)
            var s=NativeSyntheticEngineSelection();XCTAssertNil(s.claim(configuration:a,options:opts,supported:[.standaloneAWG]));XCTAssertNil(s.claimed)
            XCTAssertNotNil(s.claim(configuration:a,options:opts,supported:[.standaloneAWG],allowSplitRoute:true));XCTAssertNil(s.claim(configuration:a,options:opts,supported:[.standaloneAWG],allowSplitRoute:true))
            var bad=wg;bad[NativeSyntheticRuntimeRequest.splitKey]=mode as NSString
            XCTAssertNil(NativeSyntheticRuntimeRequest.inspect(configuration:w,options:bad,provider:.rustXray,allowSplitRoute:true))
        }
        var invalid=aw;invalid[NativeSyntheticRuntimeRequest.splitKey]="192.0.2.9" as NSString
        XCTAssertNil(NativeSyntheticRuntimeRequest.inspect(configuration:a,options:invalid,provider:.standaloneAWG,allowSplitRoute:true))
        XCTAssertNil(NativeSyntheticRuntimeRequest.inspect(configuration:a,options:aw,provider:.standaloneAWG,allowSplitRoute:true)?.splitCase)
    }
    func testFixedSyntheticPlanContainsOnlyAdjacentExcludedHosts()throws {
        let p=try NativeSyntheticSplitRoutePlan.prepare()
        XCTAssertEqual(p.included.map(\.description),["192.0.2.2/31","2001:db8::2/127"])
        XCTAssertEqual(p.excluded.map(\.description),["192.0.2.3/32","2001:db8::3/128"])
        for v6 in [false,true] {
            let yes=try NativeLiteralIPPrefix(NativeSyntheticSplitRoutePlan.target(.included,ipv6:v6)),no=try NativeLiteralIPPrefix(NativeSyntheticSplitRoutePlan.target(.excluded,ipv6:v6))
            XCTAssertTrue(p.included.contains{$0.overlaps(yes)});XCTAssertTrue(p.included.contains{$0.overlaps(no)})
            XCTAssertFalse(p.excluded.contains{$0.overlaps(yes)});XCTAssertTrue(p.excluded.contains{$0.overlaps(no)})
        }
    }

}
