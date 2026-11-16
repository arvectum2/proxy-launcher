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
