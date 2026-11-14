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

## Resumed following physical unlock — 09:20–09:27 MSK

The owner unlocked the handset. The prebuilt signed tests ran successfully.
Before any VPN activation and independently after EACH active run, the
signed read-only tests confirmed NetworkExtension OFF and all three
authenticated Keychain records accessible. Protected local per-key SHA-256
comparison proved original profiles.v1, selected profile and organization
unchanged. No raw preference file retained.

### Real hardware results

| Test | Result | Limit |
| --- | --- | --- |
| VirtualDNS synthetic address diagnosis | PASS 2.010s | Both direct name controls resolve normally; in tunnel both return one synthetic IPv4 answer. Not an authoritative leak proof. |
| Disposable same-LAN global IPv6 UDP echo | **FAIL 2.206s** | Direct control 2/2, proxy HTTPS receipt confirmed; actual UDP reply while active, independent witness echoed=4 not 3; post-OFF direct restored. Witness sits on same local IPv6 subnet, NOT an off-link internet echo host. |
| Numeric off-link IPv6 DNS/QUIC + USB RVI | PASS 6.122s | Independent filtered packet counts below; public off-link destination only, not arbitrary UDP or all DNS paths. |
| Interface-bound physical IPv6 TLS Wi-Fi → cellular → Wi-Fi | PASS 0.751s | All three independently selected NWConnection interfaces produce validated TLS/HTTP200, with VPN OFF; no global Wi-Fi toggle, no active handoff. |
| Final read-only NE/Keychain and fingerprints | PASS 2/2 | VPN OFF, 3/3 credential access, exact profiles/selection/organization parity. |

Actual installed NE route-policy booleans read from the signed app:
**includeAllNetworks=false, excludeLocalNetworks=true, enforceRoutes=false**.
This is consistent with the observed same-LAN UDP bypass; the local witness
does NOT establish an external UDP leak. Do not change the production route
policy without deciding whether LAN access should remain supported and
hardware-testing explicit exclusions/proxy reachability. We did not modify
any of these settings.

### Off-link independent RVI receipt

Genuine Network.framework QUIC h3 handshake and DNS UDP AAAA query sent
to off-link Cloudflare numeric IPv6 2606:4700:4700::1111 during exactly
three bounded phases. RVI BPF filters only that destination and UDP
destination ports 53/443. No payload logged or retained. Capture had 24
packets, zero kernel drops; raw header capture removed after counts.

| Port | Global source BEFORE | Global source DURING | Global source AFTER | Non-global DURING |
| --- | ---: | ---: | ---: | ---: |
| DNS 53 | 1 | 0 | 1 | 1 |
| QUIC 443 | 5 | 0 | 6 | 6 |

HTTPS through the disposable exclusive HTTP upstream independently proved
active real PacketTunnel. DNS returned a response (possibly VirtualDNS),
QUIC handshake failed while HTTP-only VPN active and succeeded before
and after. Independent receipt **BOUNDED_OFFLINK_PHYSICAL_UDP_NOT_OBSERVED**.
This is evidence for these two probes, not universal DNS/UDP/QUIC leak
protection. Sources with the TUN's non-global address are counted
separately. Generic off-link UDP echo against an independently hosted
server on a different subnet remains an acceptance gate.

Added explicitly opted-in physical XCTest helpers and standard-library
RVI receipt analyzer (five deterministic source-independent synthetic
cases). Signed iPhoneOS test builds PASS; Python366+5 = 371 tests
+1527 subtests PASS, Swift250/250 PASS. No production networking code
changed. Disposable processes, listener sockets and RVI removed.

### Remaining physical acceptance gates

- Decide LAN policy: preserve explicit local-network accessibility, or
  implement separately validated strict routing (including upstream
  proxy route and intentional bypass rules). Report the local UDP result
  as measured, not a pass. No configuration changed silently.
- Real Wi-Fi→cellular→Wi-Fi under **active** VPN requires a supervised
  system radio transition and operator recovery; current bound-socket
  Wi-Fi/cellular test does not satisfy that gate.
- Independent off-link general UDP witness; full DNS coverage; native
  protocol hardware QA, CloudKit live two-device, and user-data backup.
- Do not merge/publish without owner-specific approval.

## Additional off-link UDP STUN sentinel — 09:29–09:31 MSK

The same-LAN UDP echo failure was not repeated as an off-link witness.
Instead the Mac mini first sent one standard STUN Binding Request to
Cloudflare's public IPv6 STUN endpoint (stun.cloudflare.com,
2606:4700:49::, UDP/3478) and verified the matching response transaction.
A separate signed physical test then used a fresh 96-bit random
transaction ID per phase; verified success type, magic cookie, matching
transaction ID, exact aligned message length. No account or user traffic
was submitted, no mapped-address content printed or persisted.

- Signed initial NE OFF + all three Keychain credentials PASS; original
  profiles/selection/organization hash parity PASS.
- Before VPN: valid STUN Binding Success response.
- During independently confirmed disposable HTTP PacketTunnel: no
  STUN response (3-second bounded wait); tunnel still .connected at the
  end of probe; closed by explicit stop with 20s/25s safety timers.
- After confirmed OFF: valid fresh STUN response.
- Signed physical test PASS, 5.322 seconds, zero skips.
- Filtered RVI outgoing UDP/3478: **global IPv6 source counts 1/0/1**,
  one non-global source packet during the tunnel, three total packets
  captured, zero kernel drops. Receipt:
  BOUNDED_OFFLINK_PHYSICAL_UDP_NOT_OBSERVED.
- Independent signed postflight NE OFF and 3/3 Keychain PASS; original
  profiles/selection/organization SHA equality PASS. Temporary relay
  and RVI removed; raw header capture and transient preferences removed.

This adds a positive-control standard non-DNS/non-QUIC off-link UDP
probe to prior DNS53 and QUIC443 evidence. It does not assert that all
UDP destinations are protected, nor invent an independently operated
echo server: the public STUN responder returns a matching transaction
rather than a server-side count. Local IPv6 bypass remains a measured
failure against an all-UDP-blocked expectation while the existing iOS
local-network exclusion remains enabled. Active system Wi-Fi/LTE
handoff remains untested, requiring a direct operator and restoration
plan. Production NetworkExtension settings are unchanged.

Signed iPhoneOS QA build-for-testing PASS, 6 focused RVI unittest cases,
iOS Python372 + 1527 subtests PASS. No production code changes.

## Physical disposable upstream termination — 09:59–10:01 MSK

Prior PR383 exact-head CI c46acb409: Mobile iOS personal success.
User previously authorized bounded physical VPN testing; phone unlocked.

New opt-in signed test `testBoundedDisposableUpstreamFailureWithRVIWitness`
uses `APL_QA_UPSTREAM_CUT_ENABLE=YES`, the known disposable allowlisted
HTTP relay on Mac, a literal public IPv6 TLS endpoint with certificate
validation, and independent RVI. It never changes the owner profiles,
system radio settings or production route policy. Preconditions: signed
NE OFF, three existing credentials accessible, protected profile
fingerprints equal, direct public TLS positive control, and verified
distinct disposable relay egress. Host orchestrator owns the relay
subprocess; on `APL_UPSTREAM_CUT_REQUEST_<epoch>` it terminates only
that process, waits for actual process exit, and independently records
the exit epoch. The analyzer requires that receipt between cut request
and DURING start; the test asserts connected at both ends of the
six-second blocked native TLS probe. Host 20s / extension 25s safety
timeouts remain; explicit stop, OFF and restored direct TLS required.

First run: signed XCTest PASS 10.467s, relay exit confirmed, TLS failed
during the cut and recovered after VPN OFF, but RVI global-source TCP
control counts 9/0/0 (28 packets, zero capture drops). Independent
receipt INCONCLUSIVE because the post-OFF positive control was absent.
No pass attributed to this run. Added 2s route-settling delay after OFF
and 750ms padding to direct before/after positive windows only, leaving
the blocked window unchanged.

Repeated run: signed physical XCTest PASS 13.960s, independent owned
relay exit before DURING verified, TLS true/false/true. Filtered RVI,
literal external IPv6 TCP/443, global source counts BEFORE/DURING/AFTER
**11/0/11**, non-global source during 4, 39 total packets, zero drops.
Receipt BOUNDED_OFFLINK_PHYSICAL_TCP_NOT_OBSERVED. This is bounded
evidence of no direct fallback on actual upstream termination for the
tested public destination, not proof of universal leak-free behavior
or active radio handoff. Both runs: independently signed NE OFF and
3/3 existing Keychain credentials, profiles/selection/organization
fingerprint parity before/after. Temporary relay and RVI removed;
raw header capture and transient preference copies deleted.

Reproduction: build signed `ArvectumKeychainReadOnlyQA` for testing,
enable only the above opt-in in a temporary xctestrun, select the
named test, use the existing restricted QA relay with bounded lifetime,
and collect `tcpdump -i rvi0 -n -tt -l -q` with IPv6 destination
2606:4700:4700::1111 and TCP destination port 443 only. Use the host's
verified owned-process exit epoch with
`qa_offlink_rvi_receipt.py --upstream-cut-receipt EPOCH` and the test
log/capture/statistics inputs. Do not run without independent
pre/postflight OFF, protected original profile parity, cleanup and
owner authorization. Missing or late cut/positive control, test
failure or packet loss makes the negative receipt inconclusive.

Signed iPhoneOS build PASS. Python373 tests + 1527 subtests PASS,
RVI focused unittest7/7 PASS. Existing Swift core unchanged.
No production code changed. Active Wi-Fi/LTE handoff still requires
a supervised operator; LAN policy and independently operated UDP echo
server remain distinct decisions/gates.
