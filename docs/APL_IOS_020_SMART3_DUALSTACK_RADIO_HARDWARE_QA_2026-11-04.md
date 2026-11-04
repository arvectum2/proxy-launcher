# Smart3 iOS 0.2.0 — IPv6 DIRECT repair and physical Wi-Fi → LTE → Wi-Fi QA

Date: 4 Nov 2026, 00:13–01:21 MSK. Real iPhone 13, iOS 27.2, hardwired to Mac mini.
Branch: feat/ios-020-smart3-exact-flow-direct-20261103.

## Scoped IPv6 root cause and tested fix

The original interface-bound IPv6 TCP socket succeeded at TCP, but Google returned
TCP RST on TLS ClientHello over the Wi-Fi physical interface. This was NOT
evidence of absent IPv6 connectivity.

1. Debug-only Network.framework probes made HTTPS requests to AAAA-only
   ipv6.google.com on Wi-Fi and cellular. Both reached TLS-ready and returned
   HTTP bytes. USB Remote Virtual Interface (rvi0) captured distinct,
   physically real IPv6 source-address prefixes.
2. Temporary Wi-Fi-first Rust scoped IPv6: two original stalled TCP sessions
   recovered, but Wi-Fi physical sockets received TLS RST. Explicit SNI
   did not fix this.
3. Temporary cellular-first Rust scoped IPv6: two original HTTPS/TLS flows
   and one fresh TLS flow returned HTTP bytes. All three were genuine physical
   IPv6 sockets and the different exact-hostname IPv6 neighbor remained PROXY.
4. Final design prefers en0 Wi-Fi. For an exactly approved VirtualDNS
   hostname:443, it reads a complete, bounded original TLS ClientHello,
   forwards it to physical IPv6 and waits for a valid complete TLS first
   server record. If Wi-Fi fails, it retries the IDENTICAL client record
   on a bound pdp_ip* cellular socket. If neither transport returns a valid
   TLS server record, the exact host is revoked and following connections
   return to PROXY. Raw IP, UDP, other hosts, and non-TLS traffic cannot
   inherit this authorization.
5. The final design passed on real iPhone: two originally stalled HTTPS/TLS
   sessions received HTTP data without reload, a new independent HTTPS/TLS
   connection returned HTTP data, 3 real physical IPv6 DIRECT sockets,
   exactly one different IPv6 neighbor stayed upstream PROXY via CONNECT.
   USB capture showed the failed Wi-Fi TLS and successful cellular IPv6
   server response. No private user credentials or proxy profiles were used.

Rust includes bounded fragmented TLS tests, non-TLS rejection, excessive TLS
record rejection and server TLS alert handling. Rust 17/17 PASS. The updated
three-file source-pinned patch replays byte-for-byte over the verified base.

## Independent real radio route evidence

Per Apple's official Control Center documentation, tapping the Wi-Fi icon
disconnects from Wi-Fi networks but DOES NOT turn off the Wi-Fi radio:
https://support.apple.com/en-us/102412

- On the physical iPhone, Control Center Wi-Fi disconnect with armed Smart3
  DIRECT produced a genuine NWPathMonitor network change and
  smart direct reverted: network changed. The separately instrumented
  getifaddrs physical-interface snapshot continued to show Wi-Fi AND
  cellular assigned addresses, expected because Control Center only
  temporarily disconnects and maintains Wi-Fi for Continuity.
- Packet Tunnel now also independently watches physical en0 and pdp_ip*
  address/UP state (not virtual utun VPN default) and revokes all active
  DIRECT host grants if a physical interface snapshot changes. The
  actual source IPs are NEVER persisted or transmitted.
- A separate controlled 3-stage, real-hardware, per-connection underlay
  sequence on the SAME iPhone made genuine AAAA-only HTTPS requests:
  wifi-first → cellular → wifi-return. Network.framework requiredInterfaceType
  confirmed bound=1 and IPv6=1 for EACH step and each returned 512 HTTP
  bytes. Independent USB RVI capture proved all three windows
  (+/-0.85 second): 48 Wi-Fi, 56 cellular, 34 Wi-Fi outbound IPv6 packets.
  Each stage used a distinct actual physical source port and the expected
  different Wi-Fi vs cellular public-address prefix.
- These results prove exact-host route revocation on a real network event,
  plus successful real traffic over both selected physical radios.
  They DO NOT claim to have powered off the actual Wi-Fi hardware in
  iOS Settings or migrated an existing TCP socket across interfaces.
  A full Settings Wi-Fi power-off while mirroring is still not independently
  verified and can disconnect the remote GUI control.

Evidence only in owner-private local runtime:
- /private/tmp/apl-smart3-ipv6-wifi-cellretry-mock-20261104.log
- /private/tmp/apl-smart3-ipv6-wifi-cellretry-rvi-20261104.log
- /private/tmp/apl-smart3-wifi-cell-wifi-rvi-complete-20261104.log
- protected per-test after-group.plist under
  /Users/master/Library/Application Support/Arvectum/ios-020-smart3-*

After EACH physical experiment, owner App Group 11/11 and app prefs
19/19 were restored with SHA256 per-value equality. Owner phone has
optimized Release-compiled iOS 0.2.0 (48) with LIVE Yandex banner/native
ads, no test flags or actual paid profile mutations. Temporary mocks
and active VPN tunnel are stopped.

## Release and caveats

- Rust 17/17 PASS; Python iOS 176/176 +73 subtests PASS.
- Swift real iPhone Debug build-for-testing PASS.
- Pinned Rust 0.8.3 source-patch replay exactly matches tested code.
- No production ad ID or privacy metadata changes.
- ECH/DoH remain opaque; no promise of inspecting names invisible
  to VirtualDNS or general TCP migration on physical network changes.
- Apple App Review (not preliminary DTS) decides eventual acceptance.
- App Store Connect upload, merge and public release NOT performed.

## Final signed local Distribution candidate

- Apple Distribution archive:
  /private/tmp/APL-iOS-020-Smart3-DualStack-Handoff-RSYA-20261104.xcarchive
- App Store-format local IPA:
  /private/tmp/APL-iOS-020-Smart3-DualStack-Handoff-RSYA-20261104-export/Arvectum Proxy Launcher.ipa
- SHA-256: 7e716fad3a946fc4c7623acef57fe174939eae9ddf612617358ec5f1f9fe60fe
- Size 9,070,959 bytes; iOS 0.2.0 (48).
- ARCHIVE SUCCEEDED, EXPORT SUCCEEDED, ZIP intact, Apple Distribution
  app and Packet Tunnel extension deep codesign verified.
- Independent source AND actual exported IPA guard passed:
  RSYA_PRODUCTION_IPA_SDK_AND_SIGNATURE_GATE_PASS.
- Inside the signed IPA: YandexMobileAds binary, 228 SKAdNetwork IDs,
  Packet Tunnel with three explicitly verified scoped IPv6 TLS fallback
  runtime strings from Rust. These identify the exact signed artifact,
  not just the source tree.
- This IPA supersedes ALL older local 0.2.0 (48) signed candidates.
  No App Store Connect upload has taken place.
