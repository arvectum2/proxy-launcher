"""Provider-direct probe is isolated and cannot claim product VPN acceptance."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / "mobile/ios/Tools/ProviderVLESSHardwareQA"
P = (QA / "Provider.swift").read_text()
M = (QA / "ScopedTUNMetrics.swift").read_text()
W = (QA / "ScopedTCPWitness.swift").read_text()
B = (QA / "build_unsigned.sh").read_text()
H = (ROOT / "mobile/ios/Tools/NativeTunnelLab/Host/NativeLabHost.swift").read_text()

class ProviderDirectQAGate(unittest.TestCase):
    def test_exact_pinned_product_archive_and_bound_udp_config(self):
        for token in ('45716d42d434ae6d6576d9a32f47a4ea63d4943f106cb3bb7e6af57c725ea7af',
                      '1c8f00a729dac97e7670b718d6208d8e67946ea9b2260a9f68eed4a9fa5e0c54',
                      'CODE_SIGNING_ALLOWED: NO','CODE_SIGNING_REQUIRED: NO'):
            self.assertIn(token,B)
        for token in ('compileValidatedCandidate(candidate,socksPort:39879,datagramReview:true)',
                      'interfaceName:"en0",expectedAddress:"192.168.1.80",expectedPort:39882',
                      'candidate.serverName=="example.com"'):
            self.assertIn(token,P)
    def test_synthetic_scope_without_rust_tun(self):
        self.assertIn('NEIPv4Route(destinationAddress:"198.51.100.77",subnetMask:"255.255.255.255")',P)
        scoped=P.split('let ipv4=NEIPv4Settings',1)[1].split('settings.ipv4Settings=ipv4',1)[0].split('#else',1)[1]
        for token in ('default()', 'includedRoutes = [.default', 'excludedRoutes', 'dnsSettings'):
            self.assertNotIn(token,scoped)
        for token in ('packetFlow','SecItem'):
            self.assertNotIn(token,P)
        self.assertNotIn('ProviderVLESSHardwareQA',(ROOT/'mobile/ios/project.yml').read_text())
        self.assertIn('report["rustTUNStarted"]=false',P)
        self.assertIn('report["releaseAuthorized"]=false',P)
    def test_one_shot_exact_response_and_native_stop(self):
        self.assertIn('messageData==Data("apl-provider-direct-v1".utf8)',P)
        self.assertIn('consumed=true;challenge=nil',P)
        self.assertIn('nonce.utf8.count==40',P)
        self.assertIn('Array(response[split.upperBound...])==target',P)
        self.assertIn('report["nativeStopConfirmed"]=stopped',P)
        self.assertIn('NativeLabRuntime.running==false',P)
        self.assertIn('20_000_000_000',P)
    def test_scoped_tun_variant_pinned_and_drained(self):
        self.assertIn("6aea76be103f0266c54d10e049f6b9a231cc8ccaf25c59c89003bafe61b2ae16",B)
        self.assertIn("APL_PROVIDER_SCOPED_TUN_QA",P)
        self.assertIn('ExactLabTUNDescriptor.find(address:"192.0.2.177")',P)
        self.assertIn("dnsBypass:[],exactDNS:true",P)
        self.assertIn("TunnelEngineHandoff.stopAndDrain",P)
        self.assertIn('providerDirectReceipt["rustDrainConfirmed"]==true',H)
        self.assertIn('providerDirectReceipt["hostExactHTTPReceipt"]=hostExact',H)

    def test_scoped_metrics_bounded_and_no_second_external_probe(self):
        for token in ('descriptorMatchedBefore','descriptorMatchedAfter','localSOCKSGreeting','ScopedTUNMetrics.shared.stop()','apl-lab-counters-v1'):
            self.assertIn(token,P)
        self.assertIn("ScopedTUNMetrics.swift",B)
        for token in ('tun2proxy_set_log_callback(nil,nil)','tun2proxy_set_traffic_status_callback(1,nil,nil)','tun2proxy_set_flow_event_callback(nil,nil)','min(1_000_000,','min(tx,1_000_000_000)','=="198.51.100.77"','(0...7).contains(event)'):
            self.assertIn(token,M)
        for token in ('print(', 'FileManager', 'UserDefaults', 'Data(contentsOf:'):
            self.assertNotIn(token,M)
        greeting=P.split('static func greetingOnly()',1)[1].split('#endif',1)[0]
        self.assertIn('sendAll(fd,[5,1,0]) && exact(fd,2)==[5,0]',greeting)
        self.assertNotIn('198,51,100,77',greeting)
        self.assertNotIn('GET /',greeting)

    def test_host_raw_tcp_fixed_scope_and_numeric_counters(self):
        self.assertIn('ScopedTCPWitness.run(value)',H)
        self.assertIn('counters.merge(rawResult.counters){old,_ in old}',H)
        self.assertIn('counters.merge(parsed){old,_ in old}',H)
        for token in ('kind.connect(fd)','validNonce(nonce)',
                      '6_000_000_000','hostConnectErrno','hostSentBytes','hostReceivedBytes',
                      'response[split.upperBound...]==body','lengths.count==1','O_NONBLOCK'):
            self.assertIn(token,W)
        for token in ('"198.51.100.77"','"2001:db8:77::77"','UInt16(39883).bigEndian'):
            self.assertIn(token,(QA/"FixedWitnessKind.swift").read_text())
        for token in ('NSAllowsArbitraryLoads','NSExceptionDomains','IP_BOUND_IF','SO_BINDTODEVICE'):
            self.assertNotIn(token,W+B)
        self.assertIn('ScopedTCPWitness.swift',B)

    def test_full_route_qa_requires_synthetic_egress_guard(self):
        guard=(QA/"FullRouteGuard.swift").read_text()
        for token in ('"qa-drop","protocol":"blackhole"','[deny,outbound[0]]','"network":kind.network','"ip":[kind.cidr]','"port":"39883"','"outboundTag":"qa-drop"','"loglevel":"none"'):
            self.assertIn(token,guard)
        self.assertNotIn('"freedom"',guard)
        for token in ('FullRouteGuard.restrict(bound,kind:kind)','NativeExactTunnelDescriptor.find(address:"192.0.2.177",ipv6:"2001:db8:177::2")','NEIPv4Route.default()','NEIPv6Route(destinationAddress:"8000::",networkPrefixLength:1)','dns.matchDomains=[""]','report["fullRouteSyntheticGuard"]=true'):
            self.assertIn(token,P)
        self.assertIn('tun2proxy_set_log_callback({ _,_,_ in },nil)',M)
        self.assertIn('providerDirectReceipt["fullRouteSyntheticGuard"]==true',H)
        self.assertIn('APL_PROVIDER_FULL_ROUTE_QA',B)
        self.assertNotIn('APL_PROVIDER_FULL_ROUTE_QA',(ROOT/'mobile/ios/project.yml').read_text())

    def test_full_route_protocol_selection_is_bound_to_receipt(self):
        self.assertIn('FixedWitnessKind(rawValue:rawKind)',P)
        self.assertIn('options["aplFixedWitnessKind"]=probeKind as NSString',H)
        self.assertIn('providerDirectReceipt["witness_"+kind.rawValue]==true',H)
        u=(QA/"FixedUDPWitness.swift").read_text()
        self.assertIn('guard kind.udp,ScopedTCPWitness.validNonce(nonce)',u)
        self.assertEqual(u.count('Darwin.send('),1)
        self.assertIn('response==Data(("APL_RECEIPT:"+nonce).utf8)',u)

    def test_historical_lab_is_preserved_not_adopted(self):
        body=H.split('private func historicalDormantKind(',1)[1].split('private func inspectProviderManagers',1)[0]
        for token in ('!item.isEnabled','item.connection.status == .disconnected','p.passwordReference==nil','p.identityData==nil','!p.includeAllNetworks','Set(config.keys)==["aplNativeMode","aplNativeOwner"]','UUID(uuidString:owner) != nil','native-product-start-v1','APL Native Product'):
            self.assertIn(token,body)
        for token in ('saveToPreferences','removeFromPreferences','startVPNTunnel','stopVPNTunnel'):
            self.assertNotIn(token,body)
        self.assertIn('APL provider-direct synthetic QA v1',H)
        self.assertIn('preserved.allSatisfy({historicalDormantKind($0) != nil})',H)
        self.assertIn('if let existing=owned.first{return existing}',H)

    def test_census_readonly_and_explicit_lab_owned_gate(self):
        body=H.split('private func inspectProviderManagers(runID:String)',1)[1].split('#endif',1)[0]
        for token in ('loadAllFromPreferences','relatedManagers','ownedManagers','otherActive'):
            self.assertIn(token,body)
        for token in ('saveToPreferences','removeFromPreferences','startVPNTunnel','stopVPNTunnel'):
            self.assertNotIn(token,body)
        self.assertIn('guard named.count <= 1, named.allSatisfy(isOwned)',H)
        self.assertIn('providerDirectReceipt["nativeStopConfirmed"]==true',H)

if __name__=="__main__":
    unittest.main()
