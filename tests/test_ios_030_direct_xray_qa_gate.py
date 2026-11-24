"""The standalone iOS Xray diagnostic must not turn into a VPN/profile app."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
QA=ROOT/'mobile/ios/Tools/DirectVLESSHardwareQA'
SRC=(QA/'Host/DirectVLESSQA.swift').read_text()
BUILD=(QA/'build_unsigned.sh').read_text()

class DirectXrayQASafetyTests(unittest.TestCase):
    def test_explicit_one_shot_input_and_synthetic_targets(self):
        for token in ('--apl-vless-direct-qa','used=true','QAInput.consume(',
                      'Set(root.keys)==Set(["runID","nonce","link"])',
                      'candidate.serverHost=="192.168.1.80"',
                      'candidate.serverPort==39882','candidate.serverName=="example.com"',
                      'input.nonce.utf8.count==40','198,51,100,77,0x9b,0xcb'):
            self.assertIn(token,SRC)

    def test_no_vpn_or_user_account_apis(self):
        for banned in ('import NetworkExtension','import CloudKit',
                       'NEVPNManager(', 'NETunnelProviderManager(', 'SecItemCopyMatching(',
                       'UserDefaults.standard', 'UIApplication.shared.open(', 'URLSession.shared'):
            self.assertNotIn(banned,SRC)
        self.assertIn('networkExtensionUsed":false',SRC)
        self.assertIn('profilesAccessed":false',SRC)
        self.assertIn('releaseAuthorized":false',SRC)

    def test_exact_local_socks_receipt_and_native_stop_before_report(self):
        self.assertIn('"GET /\\(nonce) HTTP/1.1',SRC)
        self.assertIn('"APL_RECEIPT:\\(nonce)"',SRC)
        self.assertIn('receipt.stopped=(NativeLabRuntime.running==false)',SRC)
        self.assertIn('receipt.httpReceipt && receipt.stopped',SRC)
        self.assertLess(SRC.index('NativeLabRuntime.call("stopXray")'),SRC.index('return receipt\n    }\n}'))

    def test_bounded_no_payload_lan_control_before_xray(self):
        self.assertIn('"directLANReachable":directLANReachable',SRC)
        self.assertIn('DirectLANControl.probe()',SRC)
        self.assertIn('Darwin.poll(&ready,1,2500)',SRC)
        self.assertIn('"192.168.1.80"',SRC)
        self.assertLess(SRC.index('let lan=DirectLANControl.probe()'),
                        SRC.index('let config=try NativeLabRuntime.prepare'))

    def test_no_xray_readonly_lan_probe_and_bounded_diagnostics(self):
        self.assertIn('args.contains("--apl-vless-lan-probe")',SRC)
        self.assertIn('guard !used,lanOnly != full else{return}',SRC)
        self.assertIn('"xrayWasNotStarted":true',SRC)
        self.assertIn('import Network',SRC)
        self.assertIn('LANPrivacyControl.probe()',SRC)
        self.assertIn('Allow Local Network in iOS Settings',SRC)
        self.assertIn('connection.currentPath?.unsatisfiedReason == .localNetworkDenied',SRC)
        self.assertIn('"nwLocalNetworkDenied":privacy.localNetworkDenied',SRC)
        self.assertIn('semaphore.wait(timeout: .now() + .seconds(3))',SRC)
        self.assertIn('apl-vless-lan-control-result.json',SRC)
        self.assertIn('result.errorCode',SRC)
        self.assertIn('result.phase',SRC)
        self.assertIn('wifiOnTestSubnet',SRC)
        self.assertIn('"en0"',SRC)
        self.assertIn('0xc0a80100',SRC)
        self.assertIn('return',SRC[SRC.index('if lanOnly {'):SRC.index('guard let input=QAInput.consume')])
        self.assertLess(SRC.index('if lanOnly {'),SRC.index('guard let input=QAInput.consume'))

    def test_full_runtime_fail_closed_until_lan_is_reachable(self):
        self.assertIn('if !lan.connected {',SRC)
        self.assertIn('receipt.lanPermissionDenied=privacy.localNetworkDenied',SRC)
        self.assertIn('"localNetworkPermissionDenied" : "lanUnavailable"',SRC)
        self.assertIn('return receipt // Never start Xray against an unreachable LAN peer.',SRC)
        self.assertLess(SRC.index('if !lan.connected {'),SRC.index('let config=try NativeLabRuntime.prepare'))

    def test_product_go_variant_pinned_and_exact_compiler(self):
        self.assertIn("APL_DIRECT_PRODUCT_GO_QA",SRC)
        self.assertIn("datagramReview:true",SRC)
        self.assertIn('bindPhysicalUnderlay(raw,interfaceName:"en0",expectedAddress:"192.168.1.80",expectedPort:39882)',SRC)
        self.assertIn('lan.wifiOnTestSubnet,if_nametoindex("en0") != 0',SRC)
        self.assertIn('unifiedGoProductBoundUDP',SRC)
        self.assertIn('1c8f00a729dac97e7670b718d6208d8e67946ea9b2260a9f68eed4a9fa5e0c54',BUILD)
        self.assertIn('45716d42d434ae6d6576d9a32f47a4ea63d4943f106cb3bb7e6af57c725ea7af',BUILD)
        self.assertIn('lib=APLUnified',BUILD)
        self.assertIn('APL_DIRECT_PRODUCT_GO_QA',BUILD)

    def test_unsigned_pinned_library_and_separate_project(self):
        for token in ('verify_xray_source_candidate.py','CODE_SIGNING_ALLOWED: NO',
                      'CODE_SIGNING_REQUIRED: NO','DIRECT_XRAY','release_authorized',):
            if token=='DIRECT_XRAY':
                self.assertIn('APLDirectXrayQA',BUILD)
            elif token=='release_authorized':
                self.assertIn("'release_authorized':False",BUILD)
            else:self.assertIn(token,BUILD)
        self.assertIn('<key>CFBundleIdentifier</key>',BUILD)
        self.assertIn("PlistBuddy -c 'Print :CFBundleIdentifier'",BUILD)
        product=(ROOT/'mobile/ios/project.yml').read_text()
        self.assertNotIn('DirectVLESSHardwareQA',product)

if __name__=='__main__':unittest.main()
