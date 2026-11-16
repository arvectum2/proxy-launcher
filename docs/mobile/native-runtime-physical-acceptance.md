# Native runtime physical acceptance

Offline preparation only. Source `bf886675d2aba327bb35c48dc85e04d984e1b48e` unsigned containing ARM64 build and provider link PASS. Evidence `native-artifacts/containing-native-runtime-qa-harness-final-20261116/manifest.json`, SHA256 `16ed8927690ea2d27afbe6da9c079039f72a715158c55e434b3669d4f6f582d5`; five evidence hashes verified, 467 recorded source hashes. This is not a signed/installable candidate or runtime proof.

## Stop gates

Obtain explicit approval for exact signed build, disposable physical device, controlled peers, captures and manager changes. Existing product bundle/group identities are used: no install over owner data or new signing identities without separate approval. Rebuild pinned source and inputs using stage34 containing build script; independently verify signed host/provider digests, entitlements and profile provenance. No release signing or submission.

Old synthetic fixtures are not automatically compatible: WG needs native text host-address prefixes, full defaults and controlled DNS; AWG needs native AWG1 text, not old binary fixture; VLESS expanded mode needs a real isolated dual-stack TCP/UDP peer. Old TCP-only VLESS peer cannot pass. Adapt peers and DNS capture in approved environment before execution.

## Operator sequence

1. Launch signed QA app with `-aplNativeRuntimeReviewQA`. Confirm disposable environment, import one synthetic native profile, select, close library and export selected fixture ID. Stop if existing data/manager census rejects; do not erase owner data. Copy exported metadata JSON privately using authorized container tooling.
2. Generate fresh owner UUID per manager lifetime and unique request UUID per command. Stage private `Documents/apl-native-runtime-qa-command.json`. Relaunch QA for each action. Arm consumes command before execution; independently confirm device and peer, then execute once.
3. `prepareManager` requires exact readback and OS-off. Run positive/negative cases only with ready independent captures. If changing fixture revision, reconcile and remove old exact manager, then use new owner and selected reference. `removeManager` only after drain/OS-off and exact owner census.
4. Export `apl-native-runtime-qa-receipt-<requestID>.json`. Missing/ambiguous receipt, timeout or unexpected manager/state: stop and supervise recovery; never retry automatically or remove another VPN. Process-local lease is not a global OS lock.

## Local command creation (no device action)

From private directory with exported `fixture-ref.json`, generate preparation command:

```sh
umask 077
OWNER=$(python3 -c 'import uuid;print(str(uuid.uuid4()).upper())')
python3 - "$OWNER" prepareManager <<'PY'
import json,os,sys,uuid
r=json.load(open('fixture-ref.json'))
assert r['schema']==1 and set(r['reference'])=={'profileID','revision','kind'}
for k in ('profileID','revision'): uuid.UUID(r['reference'][k])
assert r['reference']['kind'] in ('wireGuard','amneziaWG1','vlessReality')
assert sys.argv[2] in ('prepareManager','removeManager')
c=dict(schema=1,requestID=str(uuid.uuid4()).upper(),owner=str(uuid.UUID(sys.argv[1])).upper(),reference=r['reference'],action=sys.argv[2])
with os.fdopen(os.open('apl-native-runtime-qa-command.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as f:json.dump(c,f)
PY
```

For `run`, same owner/reference and fresh request, action `run`, `probe` tcp4/tcp6/udp4/udp6, `mode` positive/wrong-key (AWG additionally wrong-psk), fresh random lowercase hex `nonce` (40 chars Xray, 48 AWG) shared privately with independent peer. Include scope `wireGuardFull` or `vlessDatagrams` for expanded cases; omit scope for AWG or legacy TCP4-only Xray. Exclusive output only; no arbitrary destinations.

## Required evidence (not performed)

| Scope | Witness | Independent evidence |
|---|---|---|
| WG full | 198.51.100.77 / 2001:db8:77::77 port 39883 | TCP/UDP v4/v6, wrong key, exact controlled DNS, no escape |
| VLESS datagrams | Same fixed addresses and port | TCP/UDP v4/v6, wrong key, scoped isolation; not full-device DNS |
| AWG1 | 192.0.2.2 / 2001:db8::2 port 39892 | TCP/UDP v4/v6, wrong key/PSK, real peer exchange |

Correlate command and receipt schema/request/owner/reference/action/scope/probe/mode; exact setup starting and stale rejected exchanges, drain drained, manager readback and OS-off. Positive response digest equals SHA256 of `APL_RECEIPT:` + nonce (Xray) or `APL:` + nonce (AWG). Negative missing digest is NOT no-leak proof. Xray TCP HTTP 200 exact body; UDP sends `APL_UDP:` + nonce; AWG sends nonce. Independently capture peer/test destination, match nonce and exact signed build. Manager-only receipts have no probe/drain. Host receipt alone cannot authorize runtime/release. `independentWitnessRequired=true`, `releaseAuthorized=false`.

Open: signed K1/K2, expanded route/DNS/peer fixtures and evidence, Wi-Fi/LTE, faults/MTU/QUIC, native notice/security acceptance, full-device VLESS DNS/domain exclusion policy, CloudKit two-device and final release approval. Earlier isolated receipts do not demonstrate this exact candidate.

## Stage 35: offline command and host receipt tooling

Use Tools/native_runtime_qa_receipt.py from the mobile/ios directory. Store
the exported fixture metadata and command record in a fresh private (0700)
operator directory; retain an immutable copy of each command before the app
consumes its device-side copy. The helper writes new files only (0600).

Example for the explicitly authorized full WireGuard test case:

```sh
python3 Tools/native_runtime_qa_receipt.py make "$PRIVATE/fixture-ref.json" \
  "$PRIVATE/apl-native-runtime-qa-command.json" --owner "$OWNER" \
  --action run --scope wireGuardFull --probe udp6 --mode positive
python3 Tools/native_runtime_qa_receipt.py verify-host \
  "$PRIVATE/apl-native-runtime-qa-command.json" "$PRIVATE/host-receipt.json"
```

For VLESS expanded tests use vlessDatagrams; AWG1 has no scope.
prepareManager/removeManager commands omit scope, probe and mode. Use a fresh
private directory for each action. The tool checks exact command/reference
correlation, distinct control request IDs, live/stale identity, terminal drain,
manager readback, OS-off and expected response hash. It rejects receipt reuse
with a different command, but is not a persistent global replay ledger. A
successful host verifier result is correlation only, not peer/capture proof.
Negative missing response is not no-leak evidence.

The optional physical_qa_contract mode of LoopbackWitness matches the new
app's fixed literal HTTP authorities, AWG and UDP challenge bytes for all
12 protocol/family/transport combinations. It remains strictly loopback-only.
It cannot substitute for the independent isolated physical peers and captures.

Read-only preflight 16.11: paired iPhone 13 is accessible; installed product
ru.arvectum.proxylauncher.ios is already version 0.3.0 (49). The new candidate
uses that same product identity, so installing over the current app is not
an approved disposable-environment test. Stop before signing for installation
or touching existing app data/managers. Choose a genuinely disposable device
or separately approve isolated identities/signing before continuing.

## Stage 36: approved isolated NativeLab installation (16.11)

The owner approved adapting, signing, installing and testing the existing
NativeLab identity on the paired iPhone. The opt-in APL_NATIVE_ISOLATED_LAB
build-copy stage forces the QA-only entry and isolated defaults and Keychain,
removes app-group/cloud access and URL types, and uses the existing two
NativeLab development profiles. Production source configuration is unchanged.
The host/provider use one explicit lab-only Keychain group; device-side
cross-process access still needs actual acceptance.

Unsigned containing ARM64 lab source f9965c19, manifest
d3fddd293ff881b8165e92bddba61157d43805bda19fe3f191d258b355e4b7ff.
Signed evidence directory
native-artifacts/isolated-nativeqa-signed-20261116-f9965c19, manifest
b8faa079afbfab2a860f3639a763aa94f291f746178ce1c5f0bc8202acfd9dad.
523 signed file hashes and strict code signature verified. Host installed
and launched via CoreDevice with the existing lab-only identifier; production
0.3.0 build 49 remained installed. Lab metadata remains the development
project's 0.2.0 build 48, not a released product version.

Observed Settings VPN connected and production PacketTunnel process on
the device. No manager action, profile mutation or tunnel start performed.
Before any manager/run action, independently confirm system VPN off and
appropriate controlled peer readiness; app-scoped manager census alone
cannot establish system-wide VPN state. Do not alter owner configuration.

## Stage 37: physical fixture import and VLESS TCP4 peer preflight

NativeLab build 91ba63e7 stages one local document fixture, validates
the fixed LAN endpoint and protocol port, consumes the file and opens the
existing review/import flow. The physical iPhone imported, saved and selected
one synthetic VLESS profile, then exported the profile and revision IDs.
NativeLab's independent VLESS TCP4 peer was built from the locally verified
macOS Xray archive and passed a real authenticated local witness preflight.
The bounded helper reconstructs fixed routing (only the documentation-address
TCP4 witness), accepts LAN relay traffic only, binds the witness and decoy to
loopback, and shuts down after the finite test. No real iPhone tunnel test yet.
Private synthetic artifacts: ~/ArvectumSafe/apl-nativeqa-stage37 on Mac mini.

The prepareManager command was consumed and the iOS VPN configuration
permission was requested. After Allow, Mirroring required Mac login
authentication. No exact manager receipt was produced when checked. Device
VPN had been independently observed OFF; no tunnel extension process or
test listeners were present at the final check. Reconcile the exact pending
manager before any fresh command; do not automatically replay permission
or remove an unknown manager.

## Stage 38: first physical scoped VLESS Reality TCP4 success (16.11)

iOS permission interrupted the original prepare receipt. Explicit readManager
verified the exact existing owner and selected fixture while OFF without
creating or changing a manager. Initial starts failed before data-plane traffic.
The actual last disconnect was APLNativeRuntimeReview:103: three additional
transport dictionary fields alongside the four required native keys. The fix
validates exactly the case-sensitive reserved aplNative namespace, bounds
total options, rejects missing and unknown reserved keys; strict persisted
configuration, owner, binding, one-use ticket and scope remain required.
Unrelated transport metadata is not used to authorize anything.

Verified source 7d0eab38; signed NativeLab manifest
542be6149576974fdee485c1e736006360ffbe39502a3f529d3693b3c85a2986.
Physical positive request 8D1F981F-8B0E-4C98-8852-C58F5899F979:
host receipt validated setup, rejection of stale epoch, nonce response,
terminal drained state, manager readback and OS OFF; independent peer
recorded one matching witness and one LAN relay connection, 2151 inbound
and 2618 outbound bytes and exact matching response SHA256. Peer exit 0.
Exact owned manager removal verified, no extension process or test listeners.
94 focused Python tests and 18 Swift NativeCredentialHandoffTests passed.
No packet capture privilege (BPF), no negative transport or expanded
protocol acceptance yet, no broad no-leak or release claim. Production
APL untouched. Private evidence under ~/ArvectumSafe/apl-nativeqa-stage37.

## Stage 39: scoped physical VLESS Reality wrong-key rejection

On the paired iPhone, exact owner readback succeeded after the permission
prompt. Test 9ECC42B7-4169-4328-BDFB-11840F4F6DB8 used the unchanged
device fixture against an independently rotated server Reality key.
The server preflight proved the matching key succeeds and the original
key fails. The device host receipt and independent peer challenge digest
matched: no expected response, 2 LAN attempts, 3994 ingress bytes,
4810 egress bytes, zero successful witnesses, peer exit 0. Host terminal
drain and OS OFF verified; no tunnel extension remains. Retain this
owned lab manager OFF for compatible expanded VLESS cases. No broad
no-leak or release assertion; WG/AWG and packet capture remain pending.

## Stage 40: physical expanded VLESS transport positives

Using the same exact owned manager and signed isolated NativeLab candidate,
the independent server allowed exactly one synthetic address and transport
per run. All three matching local controls passed, including real SOCKS5 UDP
association for the two datagram probes. Physical TCP6, UDP4 and UDP6 host
receipts matched independent challenge and response hashes; one LAN relay
and one witness each, terminal drain and OS OFF. Peer exits 0. See checkpoint
for request IDs and encrypted relay byte counts. 94 focused Python tests
passed. The VLESS TCP4 positive and wrong-key negative are in stages 38–39.
This does not establish independent packet-capture/no-leak coverage,
LTE underlay, or product release authorization. WG and AWG remain pending.

## Stage 41: scoped WireGuard positive, full-route failure

Pinned wireguard-go reference server and local transport preflight passed all
four cases. Physical scoped TCP4 request BE5B437D matched the exact independent
nonce response, one handshake in each direction and five encrypted data
packets in each direction. Terminal drain and OS OFF verified.
Full-scope TCP6 (41E6DE25) and TCP4 (B929E055) produced no response and no
accepted WG relay packets, despite successful setup, drain and local controls;
the failure is not limited to IPv6. A lab-only peer socket interface binding
experiment (951d459c; 7 Swift, 101 Python checks and signed build passed) also
failed full TCP4 (02EA460E). It is not a proven fix; experimental source
reverted. A zero accepted relay count is not independent wire capture.
Need bounded header-only physical packet capture to distinguish path loss,
and then repair/retest. No endpoint-wide exclusions, production activation,
extended WG, AWG, no-leak, or release acceptance.

### Stage 42 preparation

All four full-route WireGuard positives and the wrong-key negative were
reconciled with independent reference receipts. The original reference
AWG archive hashes match. Its LAN-scoped local preflight passed TCP4,
TCP6, UDP4, UDP6, wrong-key, wrong-PSK and both bridge UDP controls.
The AWG fixture is staged in the isolated lab container, and the prior
exact WireGuard manager removal receipt was verified. The previous
synthetic library record still requires explicit confirmed removal and
retired revision cleanup. No AWG physical data-plane result yet.

### Stage 42 completion: direct AmneziaWG witness

The signed isolated NativeLab diagnostic candidate (source ca43fcc2) was
tested without changing the product runtime. The independent reference
implementation was built from pinned upstream source with a 120-second
bounded lifetime and a QA-only single-device source-port admission rule.
Source admission unit tests and local positive, wrong-key and wrong-PSK
controls passed. A fresh exact manager readback DA458B58 confirmed ownership
and OFF before testing. Physical receipts matched independent reference
observations: TCP4 9504B963 (7/11 sent/received), TCP6 9415666A (6/19),
UDP4 D8025EC5 (2/15), UDP6 0B60FAF9 (2/19), wrong-key D15966FC (0/1),
wrong-PSK 27577665 (1/1). Positive probes each had one exact corresponding
witness; negative probes had zero and no matching application response.
All six had terminal drain and OS OFF. Final 104 focused Python tests passed.
No remaining extension or peer listener was observed. Exact lab manager
retained OFF for follow-up. The core physical protocol matrix is 16/16,
not full production, device-wide no-leak, or release acceptance. RVI
interference with Mirroring remains a limitation for independent capture.

### Stage 43a: positive system DNS path

An isolated QA-only hostname probe (source 342f77b9) uses a unique
48-hex-label name in .apl-nativeqa.test. The independent DNS reference
responds only to that exact question, with a controlled A answer and
AAAA NODATA, inside the AWG tunnel. It does not recurse or log queries.
Go exact-name unit tests, separate-process controls and actual local
tunneled DNS plus TCP passed. 105 focused Python tests passed.
The new isolated containing build and signed install passed. Fresh
manager readback F814F910 confirmed ownership and OFF before testing.

Physical request F20DEBD4: three A responses, one exact TCP4 witness,
13 peer packets sent and 40 received; command/host/peer challenge
and response hashes matched and drain/OS OFF were verified. No
remaining peer listener or extension was observed.

This is evidence for a positive system resolver path on AWG, not proof
against parallel DNS or IP escape. WireGuard system DNS remains open;
VLESS datagram mode is scoped and does not constitute a full-device DNS
claim. A subsequent leak gate requires an independently observable
external synthetic canary, a verified outside-tunnel positive control,
and a tunnel-side witness. A missing response alone is not evidence of
no escape. Prior RVI interference and the need for specific approval
before changing gateway/device network remain constraints. No production
activation or release authorization.

### Stage 43b: WireGuard system DNS preparation and regression

The pinned independent wireguard-go reference now has a DNS-only QA
variant with exact generated name, controlled A answer, and AAAA NODATA.
Its Go unit tests, separate-process DNS + TCP and matching fixture-key
positive controls passed. The isolated native QA command accepts DNS4
only for full-scope WireGuard or AWG, positive mode. 314 iOS 030 Python
tests plus 14 subtests passed after correcting a stale clipboard count
test to enforce both user-initiated guarded preview paths. 92 targeted
Swift tests of catalog/migration/backup, credential handoff and route
plans passed. Source eede081d compiled, signed and installed as
NativeLab only. Exact AWG manager removal and retired lab revision
cleanup were verified, and the new WireGuard fixture selected/exported.
Physical WireGuard system DNS and independently witnessed leak absence
are still pending. The existing older RVI off-link probes are not
evidence of this native candidate. No production release authorization.

Stage 43b physical completion: fresh manager readback F82C9AD1 confirmed
the exact WireGuard owner and OFF. Request 6DF744B3 used the signed
isolated eede081d candidate, positive full-route scope. Independent
fixture-key control passed, one exact A response and one TCP4 witness
were observed. Relay counts c2s1=1, c2s4=15, s2c2=1, s2c4=7.
Command/host/peer challenge and response hashes correlated. Terminal
drain and OS OFF verified, no peer listener or extension remaining.
Both full-route protocols now have positive system DNS evidence;
this does not establish absence of DNS/IP escape.

### Stage 43c: independent escape acceptance gate

Pending physical observation, not a passed test. Test only disposable
NativeLab credentials and synthetic destinations under operator control.
Do not collect normal application traffic or user DNS names. Do not
infer lack of escape from a failed request or tunnel-side counters.

| Condition | Required independent evidence |
|---|---|
| VPN OFF before | Exact synthetic DNS, IPv4 and IPv6 canaries observed outside the tunnel; unavailable family is inconclusive |
| VPN ON, healthy | Exact tunnel witness and no matching external cleartext/escape witness during bounded observation |
| VPN ON, peer lost | Independently timed test-peer shutdown; no matching escape canary while failed closed |
| VPN OFF after | Same external observation path verified with fresh positive controls |
| Split route (if enabled) | Included and excluded synthetic destinations each observed only on their intended path |
| Handoff | Repeat appropriate controls across each supported Wi-Fi/cellular transition |

The external observer must have visibility of the actual underlay,
including non-LAN destinations and both address families. A peer's
LAN interface alone cannot see all phone traffic. A silent, dropped,
unreachable, or ambiguous capture is inconclusive. Correlate exact
candidate identity, command IDs, fresh challenges, observation windows,
and terminal VPN state. Record only bounded synthetic evidence, with
private permissions and no credentials in Git. No release claim until
all required gates and signed migration/production QA are satisfied.

Operator approval is required before changing Wi-Fi/cellular settings,
gateway/SSID, or capture scope. Preferred next step is wired USB RVI
with a strictly filtered, synthetic-only capture and separately
supervised device control; however, prior RVI interrupted Mirroring.
If that limitation persists, use an approved independent test gateway
or observation network instead. Do not weaken device authorization or
silently switch the user's network.

Stage 43c partial physical result: owner authorized bounded synthetic-only
USB RVI and temporary Wi-Fi/LTE transitions. RVI recovered with PKTAP
interface/direction metadata. The isolated e5108c7f candidate implements
explicit OFF controls with exact owned manager readback before and after.
Capture is restricted to fixed synthetic UDP destinations/ports and
header summaries only. No raw packet file or user DNS capture.
WG healthy UDP4 before/on/after (7D1F67FA / 14749DDA / 8CA3DB1D)
physical-out counts 1/0/1; tunnel-out counts 0/1/0. Independent peer and
host challenge-response match, zero capture drops and terminal OFF.
IPv6 before DCC4C2E4 and fixed DNS before 35670F8B each yielded one
physical-out packet, zero tunnel-out. Initial DNS attempt unconsumed
because Mirroring lost foreground; discarded rather than counted.
320 Python checks + 14 subtests passed. RVI removed; network settings
unchanged. This is bounded healthy UDP4 evidence only, not a general
no-leak result. IPv6/DNS ON and AFTER, peer loss, handoff and production
acceptance remain pending.

Stage 43c healthy WG completion: the remaining independent before/ON/after
cycles were verified with exact command/host/peer identities and ordered
capture windows. UDP6 DCC4C2E4 / 1095D8EF / 77BFEAE2 had physical-out
1/0/1 and tunnel-out 0/1/0. DNS 35670F8B / 7D812ADF / 9E3B9B9A
had physical-out 1/0/1 and tunnel-out 0/12/0; independent A witness 1
and exact subsequent TCP response. DNS OFF controls were direct synthetic
UDP queries to the fixed resolver, not system resolver tests.
All nine observations (including UDP4) correlated successfully, with no
capture drops or ambiguous metadata; terminal OS OFF and RVI cleanup
verified. Networks unchanged. This establishes bounded healthy full-route
WireGuard behavior for these exact destinations, not absence of traffic
to arbitrary DNS servers, other destinations, failure, handoff, or other
protocols. Established peer-loss testing must first prove a working
exchange, independently time a peer cut and then observe a fresh probe.

### Stage 43c: established WireGuard peer loss

Signed isolated QA source 3f0dcfde adds an exact two-probe UDP loss case.
The independent pinned wireguard-go reference emits a marker only after
the first exact synthetic response. Its owned session and sockets are
stopped, with cut timestamps recorded. The device requires a valid first
response, then sends a distinct challenge after the bounded wait without
restarting or reconfiguring the tunnel. The verifier rejects missing or
misordered cut evidence, unexpected responses, and physical egress or
ambiguous/incomplete RVI metadata.

Physical UDP4 2629B769 / 70056527 / C08B4621 and UDP6 B078C89B /
F22E06B3 / 65A58F52: for each family one physical packet in both OFF
controls; one tunnel packet before the cut and one after, zero physical
packets during the ON observation. First response and independent peer
matched; second response absent after independently confirmed shutdown.
All six ordered host/capture observations verified, zero capture drops,
terminal OS OFF. Local reference trigger controls and 321 Python tests
plus 14 subtests passed; previous 416 Swift Core results remain recorded.
No RVI interface, lab peer listener or tunnel extension remained.
No settings/network changes. This is bounded UDP evidence for established
peer loss, not a general kill-switch guarantee. DNS on peer loss,
AmneziaWG escape observations, network handoff, migration and production
release gates remain open.
