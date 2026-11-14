import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class TransportBackendContractTests: XCTestCase {
    private func plan(_ proto: TransportProtocol = .wireGuard,
                      _ capabilities: Set<TransportProbeCapability> = [.tcpIPv4],
                      scope: TransportBackendPlan.Scope = .syntheticLab,
                      routes: TransportBackendPlan.RoutePolicy = .tunnelOnly,
                      id: UUID = UUID(), revision: UUID = UUID()) throws -> TransportBackendPlan {
        try .prepare(profileID: id, revision: revision, protocol: proto, scope: scope,
                     routes: routes, required: capabilities)
    }

    func testExplicitEvidenceAndSeparateProviders() throws {
        let vless = try plan(.vlessReality)
        let wg = try plan(.wireGuard,[.tcpIPv4,.tcpIPv6,.udpIPv4,.udpIPv6])
        let awg = try plan(.amneziaWG1,[.rawIPv4,.rawIPv6])
        XCTAssertEqual(vless.provider,.rustXray)
        XCTAssertEqual(wg.provider,.rustXray)
        XCTAssertEqual(awg.provider,.standaloneAWG)
        XCTAssertThrowsError(try awg.validateProvider(.rustXray))
        XCTAssertThrowsError(try wg.validateProvider(.standaloneAWG))
        XCTAssertNoThrow(try awg.validateProvider(.standaloneAWG))
    }

    func testNoProductionOrUnsupportedRoutesOrSilentDowngrade() throws {
        for proto in [TransportProtocol.vlessReality,.wireGuard,.amneziaWG1,.amneziaWG2,.amneziaWG3] {
            XCTAssertThrowsError(try plan(proto,scope:.production)) {
                XCTAssertEqual($0 as? TransportContractError,.productionNotAccepted)
            }
            for routes in [TransportBackendPlan.RoutePolicy.directFallback,.exclusions] {
                XCTAssertThrowsError(try plan(proto,routes:routes)) {
                    XCTAssertEqual($0 as? TransportContractError,.unsupportedRoutePolicy)
                }
            }
        }
        for proto in [TransportProtocol.amneziaWG2,.amneziaWG3] {
            XCTAssertThrowsError(try plan(proto)) {
                XCTAssertEqual($0 as? TransportContractError,.unsupportedProtocol)
            }
        }
        for cap in [TransportProbeCapability.dns,.quic,.mtu,.exactHostDirect,.applicationExclusions,.rawIPv4] {
            XCTAssertThrowsError(try plan(.wireGuard,[cap]))
        }
        XCTAssertThrowsError(try plan(.vlessReality,[.udpIPv4]))
        XCTAssertThrowsError(try plan(.amneziaWG1,[.tcpIPv4]))
        XCTAssertThrowsError(try plan(.wireGuard,[]))
    }

    func testSwitchRequiresBothAcknowledgmentsInEitherOrder() throws {
        for nativeFirst in [true,false] {
            var c = TransportBackendCoordinator()
            let wg = try plan(), awg = try plan(.amneziaWG1,[.rawIPv4])
            guard case .start(let old) = try c.begin(wg) else { return XCTFail() }
            XCTAssertNil(try c.ready(old.token,provider:.rustXray))
            XCTAssertEqual(try c.requestSwitch(to:awg,token:old.token),.stop(old))
            XCTAssertThrowsError(try c.begin(awg))
            XCTAssertThrowsError(try c.requestSwitch(to:wg,token:old.token))
            if nativeFirst {
                XCTAssertNil(try c.acknowledgeNativeDrain(old.token))
                XCTAssertNil(try c.acknowledgeNativeDrain(old.token))
            } else {
                XCTAssertNil(try c.acknowledgeOSDisconnected(old.token))
                XCTAssertNil(try c.acknowledgeOSDisconnected(old.token))
            }
            XCTAssertEqual(c.active,old)
            XCTAssertEqual(c.phase,.stopping)
            let next = try nativeFirst ? c.acknowledgeOSDisconnected(old.token) : c.acknowledgeNativeDrain(old.token)
            guard case .start(let new)? = next else { return XCTFail() }
            XCTAssertEqual(new.plan,awg)
            XCTAssertEqual(new.token.generation,old.token.generation+1)
            XCTAssertEqual(c.phase,.starting)
            XCTAssertThrowsError(try c.ready(old.token,provider:.rustXray))
            XCTAssertThrowsError(try c.acknowledgeNativeDrain(old.token))
            XCTAssertThrowsError(try c.failClosed(old.token))
            XCTAssertNil(try c.ready(new.token,provider:.standaloneAWG))
            XCTAssertEqual(c.phase,.running)
        }
    }

    func testStopDuringSwitchCancelsPendingStart() throws {
        var c=TransportBackendCoordinator()
        guard case .start(let s)=try c.begin(plan()) else{return XCTFail()}
        _=try c.ready(s.token,provider:.rustXray)
        _=try c.requestSwitch(to:plan(.vlessReality),token:s.token)
        XCTAssertNil(try c.acknowledgeNativeDrain(s.token))
        XCTAssertNil(try c.requestStop(s.token))
        XCTAssertNil(c.pending)
        XCTAssertNil(try c.acknowledgeOSDisconnected(s.token))
        XCTAssertNil(c.active)
        XCTAssertEqual(c.phase,.idle)
        guard case .start(let next)=try c.begin(plan()) else{return XCTFail()}
        XCTAssertEqual(next.token.generation,s.token.generation+1)
    }

    func testStopDuringStartupAndLateReady() throws {
        var c=TransportBackendCoordinator()
        guard case .start(let s)=try c.begin(plan()) else{return XCTFail()}
        XCTAssertEqual(try c.requestStop(s.token),.stop(s))
        XCTAssertThrowsError(try c.ready(s.token,provider:.rustXray))
        XCTAssertNil(try c.acknowledgeOSDisconnected(s.token))
        XCTAssertNil(try c.acknowledgeNativeDrain(s.token))
        XCTAssertEqual(c.phase,.idle)
    }

    func testFailurePoisonsAndRemovesReplacement() throws {
        for stage in [TransportBackendCoordinator.Phase.starting,.running,.stopping] {
            var c=TransportBackendCoordinator()
            guard case .start(let s)=try c.begin(plan()) else{return XCTFail()}
            if stage != .starting {_=try c.ready(s.token,provider:.rustXray)}
            if stage == .stopping {
                _=try c.requestSwitch(to:plan(.amneziaWG1,[.rawIPv4]),token:s.token)
                XCTAssertNil(try c.acknowledgeNativeDrain(s.token))
            }
            XCTAssertEqual(try c.failClosed(s.token),.cancelTunnel(s))
            XCTAssertNil(try c.failClosed(s.token))
            XCTAssertNil(c.pending)
            XCTAssertEqual(c.active,s)
            XCTAssertEqual(c.phase,.failedClosed)
            XCTAssertThrowsError(try c.begin(plan()))
            XCTAssertThrowsError(try c.requestSwitch(to:plan(),token:s.token))
            XCTAssertThrowsError(try c.acknowledgeOSDisconnected(s.token))
            XCTAssertThrowsError(try c.acknowledgeNativeDrain(s.token))
        }
    }

    func testWrongProviderAutomaticallyCancels() throws {
        var c=TransportBackendCoordinator()
        guard case .start(let s)=try c.begin(plan()) else{return XCTFail()}
        XCTAssertEqual(try c.ready(s.token,provider:.standaloneAWG),.cancelTunnel(s))
        XCTAssertEqual(c.phase,.failedClosed)
    }

    func testSamePlanRejectedButNewRevisionRequiresDrain() throws {
        var c=TransportBackendCoordinator()
        let p=try plan()
        guard case .start(let s)=try c.begin(p) else{return XCTFail()}
        _=try c.ready(s.token,provider:.rustXray)
        XCTAssertThrowsError(try c.requestSwitch(to:p,token:s.token))
        let changed=try plan(id:p.profileID,revision:UUID())
        XCTAssertEqual(try c.requestSwitch(to:changed,token:s.token),.stop(s))
        XCTAssertNil(try c.acknowledgeOSDisconnected(s.token))
        guard case .start(let next)?=try c.acknowledgeNativeDrain(s.token) else{return XCTFail()}
        XCTAssertEqual(next.plan,changed)
    }

    func testFreshCoordinatorRejectsOldEpochEvenAtSameGeneration() throws {
        var old=TransportBackendCoordinator(), new=TransportBackendCoordinator()
        guard case .start(let a)=try old.begin(plan()),case .start(let b)=try new.begin(plan()) else{return XCTFail()}
        XCTAssertEqual(a.token.generation,b.token.generation)
        XCTAssertNotEqual(a.token.epoch,b.token.epoch)
        XCTAssertThrowsError(try new.ready(a.token,provider:.rustXray))
        XCTAssertThrowsError(try new.failClosed(a.token))
        XCTAssertEqual(new.active,b)
        XCTAssertEqual(new.phase,.starting)
    }

    func testAcknowledgmentsOutsideStopCannotReleaseRuntime() throws {
        var c=TransportBackendCoordinator()
        guard case .start(let s)=try c.begin(plan()) else{return XCTFail()}
        XCTAssertThrowsError(try c.acknowledgeNativeDrain(s.token))
        XCTAssertThrowsError(try c.acknowledgeOSDisconnected(s.token))
        XCTAssertNil(try c.ready(s.token,provider:.rustXray))
        XCTAssertThrowsError(try c.acknowledgeNativeDrain(s.token))
        XCTAssertThrowsError(try c.acknowledgeOSDisconnected(s.token))
        XCTAssertEqual(c.active,s)
        XCTAssertEqual(c.phase,.running)
        XCTAssertFalse(c.nativeDrained)
        XCTAssertFalse(c.osDisconnected)
    }

    func testReverseSwitchAndSameEngineSwitchNeverOverlap() throws {
        var c=TransportBackendCoordinator()
        let plans=[try plan(.amneziaWG1,[.rawIPv6]),try plan(.wireGuard,[.udpIPv6]),try plan(.vlessReality)]
        guard case .start(let first)=try c.begin(plans[0]) else{return XCTFail()}
        var current=first
        for target in plans.dropFirst() {
            XCTAssertNil(try c.ready(current.token,provider:current.plan.provider))
            XCTAssertEqual(try c.requestSwitch(to:target,token:current.token),.stop(current))
            XCTAssertNil(try c.acknowledgeOSDisconnected(current.token))
            XCTAssertEqual(c.active,current)
            guard case .start(let next)?=try c.acknowledgeNativeDrain(current.token) else{return XCTFail()}
            XCTAssertEqual(next.plan,target)
            XCTAssertThrowsError(try c.acknowledgeOSDisconnected(current.token))
            current=next
        }
        XCTAssertNil(try c.ready(current.token,provider:current.plan.provider))
        XCTAssertEqual(c.active?.plan.wireProtocol,.vlessReality)
    }

    func testParsedWGFormatCannotDowngradeOrMasquerade() throws {
        let key=Data(repeating:0x22,count:32).base64EncodedString()
        let head="[Interface]\nPrivateKey = "+key+"\nAddress = 192.0.2.1/32\n"
        let tail="[Peer]\nPublicKey = "+key+"\nEndpoint = 127.0.0.1:39881\nAllowedIPs = 198.51.100.77/32\n"
        let extra="Jc = 3\nJmin = 32\nJmax = 120\nS1 = 15\nS2 = 18\nH1 = 123456\nH2 = 67543\nH3 = 123123\nH4 = 32345\n"
        let wg=try WGQuickConfigurationPreview.parse(head+tail)
        let awg=try WGQuickConfigurationPreview.parse(head+extra+tail)
        let w=try plan(), a=try plan(.amneziaWG1,[.rawIPv4])
        XCTAssertNoThrow(try w.validateWGPreview(wg))
        XCTAssertNoThrow(try a.validateWGPreview(awg))
        XCTAssertThrowsError(try w.validateWGPreview(awg)) {
            XCTAssertEqual($0 as? TransportContractError,.profileFormatMismatch)
        }
        XCTAssertThrowsError(try a.validateWGPreview(wg))
        XCTAssertThrowsError(try plan(.vlessReality).validateWGPreview(wg))
        XCTAssertThrowsError(try WGQuickConfigurationPreview.parse(head+extra+"S3 = 42\n"+tail))
    }

    func testSameProfileRevisionCannotChangeProtocol() throws {
        var c=TransportBackendCoordinator()
        let p=try plan()
        guard case .start(let s)=try c.begin(p) else{return XCTFail()}
        _=try c.ready(s.token,provider:.rustXray)
        let impostor=try plan(.vlessReality,id:p.profileID,revision:p.revision)
        XCTAssertThrowsError(try c.requestSwitch(to:impostor,token:s.token))
        XCTAssertEqual(c.active,s)
        XCTAssertNil(c.pending)
    }
}
