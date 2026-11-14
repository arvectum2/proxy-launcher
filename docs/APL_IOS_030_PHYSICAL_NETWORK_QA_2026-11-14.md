# iOS 0.3.0 — authorized physical network QA preparation and lock blocker

Date: **14 November 2026, 04:26–04:31 Moscow**. Explicit owner authorization was given in chat for bounded physical DNS/UDP/QUIC and Wi-Fi/LTE VPN testing. Device: paired iPhone 13, iOS 27.2.1, installed APL 0.3.0 (49), connected to Mac mini through USB and iPhone Mirroring.

## Baseline / reversible safety checks

- Production `main` remained clean at `0a68fbb4a`. Source branch for this stage: `qa/ios-030-physical-network-20261114` based on QA PR #382. The prior source-only integration Draft PR #381 and synthetic Files QA are kept intact.
- Device was visible as a paired, connected physical iPhone. A protected, access-restricted **local-only** copy of `group.ru.arvectum.proxylauncher.ios` preferences was made before touching VPN. It had 14 keys, including an existing `profiles.v1` payload (431 bytes) and selected profile ID. No profile address, password or identifier was printed or committed.
- After the attempted signed test start, an independent second CoreDevice copy was compared with the baseline. **Entire App Group preference plist byte-for-byte identical**, `profiles.v1` byte-identical, `selected_profile_id` identical, profile organization identical. No Device Keychain password contents accessed or logged. The two temporary raw plist copies were deleted after comparison; only local SHA-256 fingerprints remain in a mode-0600 file inside a mode-0700 temporary directory on Mac mini, not in Git.
- Signed Debug `ArvectumKeychainReadOnlyQA` **build-for-testing SUCCEEDED** for generic iPhoneOS ARM64 with `DEBUG APL_RUN_EXPLICIT_VPN_QA`. Signed App and PacketTunnel have the same known Apple team `VML75VY94V`, identical App Group and Keychain access group entitlements. Full test runner `.xctestrun` generated in `/tmp/apl-ios-030-physical-network-20261114/Build/Products`.
- The independent read-only signed Xcode tests for **system NetworkExtension OFF** and **three existing Keychain records** were **NOT run**. Xcode's actual message: `Unlock iPhone Nikita to Continue` / `Xcode cannot launch PhysicalKeychainReadOnlyTests ... because the device is locked`. The waiting Xcode job was explicitly terminated; no live VPN test was launched. iPhone Mirroring is able to show the phone while it is physically locked, but this is not equivalent to physical device unlock required by Xcode XCTest.
- Extra local-only laboratory self-test: temporary no-secrets public-global-IPv6 UDP echo server from `qa_udp_echo_witness.py` returned **2/2 test nonces** in 5s, `echoed=2 rejected=0`, then self-terminated. There are **no residual UDP:18991 / TCP:18081 listeners**. This proves the Mac mini test server works locally; it does **not** prove public reachability from the iPhone or absence of a VPN UDP leak.

## Next test execution order (only after physical handset unlock)

1. Confirm iPhone directly unlocked on the handset (Xcode device test destination ready), cable still attached. Keep the user's original APL profiles unchanged and never log the proxy addresses, secrets or selected UUID.
2. Refresh protected App Group baseline, run only the two signed **read-only** `PhysicalVPNStatusReadOnlyTests/testAPLNetworkExtensionIsDisconnectedBeforeActiveQA` and `PhysicalKeychainReadOnlyTests/testThreeExistingAuthenticatedProfilesCanReadKeychainWithoutMutation`. STOP if OFF or 3/3 credential access fails.
3. Start exactly one **allowlisted, time-bounded** LAN IPv6-only CONNECT QA proxy on Mac mini (192.168.1.80:18081), with hardcoded allowed HTTPS 443 destinations, no credentials. Preflight its health before any VPN on iPhone.
4. Run one explicitly selected signed physical DNS diagnostic with `qaStopAfterSeconds=25` in PacketTunnel, plus independent 20s host stop and `defer stopVPNTunnel`. Collect only non-secret codes, DNS address-family counts and synthetic `198.18/15` observations. This is a **DNS diagnostic**, NOT independent DNS leak acceptance; authoritative DNS/underlay observation is still required.
5. Only if independent public IPv6 UDP witness can be reached twice from iPhone while VPN OFF and the disposable proxy preflight succeeds, execute `PhysicalDisposableIPv6UpstreamTests/testBoundedUDPDirectWitnessBlockedInPacketTunnelAndRestored` with explicit `APL_QA_UDP_ENABLE=YES` and bound witness endpoint. Require exactly **3** server echoes: two before and one after, never four. No echo on iPhone while VPN on alone is not sufficient proof. Never run with owner commercial proxy profiles.
6. If all previous steps pass and a direct phone operator is present, carry out controlled Wi-Fi/LTE transition in a separate narrowly scoped scenario with hardware watchdog and restoring Wi-Fi. iPhone Mirroring may disconnect when Wi-Fi is disabled; **do not blindly toggle it while the handset cannot be directly operated**. QUIC UDP/443 requires a distinct packet witness and must not be inferred from UDP echo.
7. Independently repeat signed NetworkExtension OFF and 3/3 Keychain tests, copy App Group preferences and compare `profiles.v1`, selected ID, organization byte-for-byte to pre-test. No app reinstall/reset, no App Store upload or PR merge. Any failed independent OFF receipt **blocks further traffic tests**.

## Current acceptance

- [x] Permission for short physical VPN/network testing obtained.
- [x] Protected original App Group snapshot and post-attempt byte parity; signed QA build-for-testing and matching entitlement identity.
- [x] Disposable UDP witness local self-test 2/2, no persistent server.
- [ ] **Blocked: physical iPhone must be unlocked directly** for Xcode signed XCTest; the Mirroring session does not satisfy the device-lock gate.
- [ ] Independent NetworkExtension OFF, 3/3 Keychain access, any real VPN start/stop.
- [ ] DNS authoritative underlay leak proof, UDP witness from actual iPhone, QUIC UDP/443, Wi-Fi/LTE transition, post-test signed OFF and profiles parity.

**Do not mark physical DNS/UDP/QUIC or Wi-Fi/LTE accepted.** This stage caused no VPN activation and did not modify owner profiles.
