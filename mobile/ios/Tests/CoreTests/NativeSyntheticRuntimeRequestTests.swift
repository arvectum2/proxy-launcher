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
}
