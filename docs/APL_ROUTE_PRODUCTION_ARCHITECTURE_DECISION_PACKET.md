# APL-ROUTE — Windows production enforcement architecture decision packet

Status: `OWNER REVIEW REQUIRED / no production architecture approved`
Date: `2026-09-19`
Source: `docs/LOCAL_EXECUTION_BACKLOG.md#P8`
Related: `APL-ROUTE-001..004`

## 1. Decision to make

Choose the Windows production enforcement architecture for user-selected per-application proxy/direct routing.

This packet is preparation only. It does not authorize privileged installation, driver deployment, production traffic mutation, signing, release publication, or selection of a new paid/material dependency.

## 2. Already-established product facts

The repository has already proven the following control-plane pieces:

- `APL-ROUTE-001` defines deterministic application/destination/action rules without pretending every platform can enforce every rule.
- `APL-ROUTE-002` established Windows as the first feasible production target and identified WFP ALE application-layer enforcement as the native architecture family.
- `APL-ROUTE-003` uses the real Windows WFP `FwpmGetAppIdFromFileName0` application identity API and compiles rules into a non-mutating ALE connect-redirect filter plan.
- `APL-ROUTE-004` defines durable ownership/recovery state: prepared -> applied -> restoring -> verified cleanup, Arvectum-only resource identities, plan digest binding, fail-closed recovery, and no deletion of foreign firewall/WFP resources.

### Current v0.2.10 safety baseline

The production decision is evaluated against the published `v0.2.10` desktop baseline. `v0.2.10` preserves the saved-or-Arvectum rollback-safety contract established in `v0.2.9` while promoting the governed AppImage lane; it does not broaden Windows host-mutation authority. Windows, Astra/Fly and RED OS/KDE therefore continue to share the same ownership rule: if the host presents a third/foreign proxy state, Proxy Launcher fails closed and preserves durable rollback evidence instead of overwriting that state. Any future per-application enforcement plane must preserve that invariant rather than introducing broader privileged cleanup authority.

Consequently, an approved Windows enforcement implementation must keep WFP/service ownership evidence separate from system-proxy rollback evidence, must never treat unrelated WFP/firewall/VPN/EDR resources as Arvectum-owned, and must make update/uninstall recovery verifiable before deleting its own durable ownership journal. This refresh does not approve an architecture; it only carries the current stable safety contract into the Owner decision.

The missing work is therefore not “how to represent routing rules.” It is choosing and proving the **privileged enforcement plane**.

## 3. Microsoft-native mechanism

Microsoft documents WFP ALE connect redirection as the native mechanism for redirecting an application's connection to a local proxy service. The important production implications are:

- application identity can be filtered at ALE using WFP application-id conditions;
- `FWPM_LAYER_ALE_CONNECT_REDIRECT_V4/V6` can modify the remote address/port for the lifetime of a connection;
- the redirector is a callout driver/native privileged component, while the proxy service accepts the redirected connection and creates the outbound proxied connection;
- WFP redirect records/context must be carried onto the proxy's outbound socket so Windows and other inspection agents can track the proxied flow;
- the implementation must detect its own previously redirected traffic and avoid redirect loops;
- TCP and UDP are supported by the WFP redirection architecture, but UDP behavior has additional edge cases and must be tested explicitly rather than inferred from TCP success.

Microsoft references checked 2026-09-14 and retained as the mechanism baseline for this repository decision packet:

- https://learn.microsoft.com/windows-hardware/drivers/network/using-bind-or-connect-redirection
- https://learn.microsoft.com/windows-hardware/drivers/network/using-proxied-connections-tracking
- https://learn.microsoft.com/windows/win32/fwp/ale-layers
- https://learn.microsoft.com/windows/win32/winsock/sio-set-wfp-connection-redirect-records

## 4. Architecture options

### Option A — Arvectum-owned WFP ALE callout + narrow Windows service + local proxy

Shape:

`GUI/control plane -> authenticated local IPC -> privileged Arvectum service/callout -> WFP ALE connect redirect -> local proxy -> upstream proxy/direct target`

The native component owns only Arvectum provider/sublayer/callout/filter resources. The existing Python/UI layer remains unprivileged and sends schema-validated plans, not arbitrary firewall commands.

Advantages:

- aligns directly with the WFP mechanism already selected and prototyped by APL-ROUTE-002/003;
- strong process identity through WFP application id;
- deterministic ownership and cleanup can consume APL-ROUTE-004 directly;
- no need to replace the entire Windows network stack or force all traffic through a virtual adapter;
- can keep existing local proxy semantics and target only selected applications.

Costs/risks:

- kernel/native callout and privileged service create a materially higher security and release burden;
- driver/service signing, update, rollback and uninstall must be production-grade;
- TCP/UDP/IPv4/IPv6, loop prevention, multiple security products/proxies and crash/reboot behavior need physical Windows acceptance;
- domain selectors remain a separate DNS lifecycle problem and must not be implemented as a one-time hostname-to-IP expansion.

### Option B — Third-party WFP/redirect driver or interception SDK

Shape:

`Arvectum control plane -> third-party signed interception component/SDK -> local proxy`

Advantages:

- may reduce custom kernel engineering;
- may provide ready-made process attribution/redirection and signed driver distribution.

Costs/risks:

- introduces a material external dependency into a sensitive privileged boundary;
- sovereignty, licensing, SBOM, vulnerability response, supply-chain continuity and Russian-registry implications must be evaluated;
- vendor behavior can constrain recovery semantics or make exact APL-ROUTE-004 ownership guarantees harder to prove;
- paid/commercial dependency requires explicit Owner approval.

This is not automatically safer than Option A merely because less code is written by Arvectum.

### Option C — Full virtual adapter/TUN/VPN enforcement on Windows

Shape:

`virtual adapter -> packet engine -> process attribution/policy -> proxy/direct egress`

Advantages:

- broad traffic visibility and future protocol flexibility;
- conceptually closer to the mobile system-VPN model.

Costs/risks:

- per-process identity still requires a reliable Windows attribution layer; a TUN packet alone does not naturally contain executable identity;
- substantially broader blast radius because all or much of host traffic traverses the enforcement stack;
- DNS, route ownership, kill/recovery, coexistence with corporate VPNs and other filter drivers become more complex;
- likely over-scoped for the current requirement, which is selected-app proxy/direct routing rather than a general Windows VPN product.

### Option D — system proxy/PAC/environment/process configuration tricks

Not suitable as the production enforcement architecture.

Reasons:

- many applications bypass WinINET/system proxy settings;
- environment variables require application cooperation and do not reliably cover arbitrary installed Windows software;
- PAC is destination-oriented rather than strong process enforcement;
- these methods cannot honestly satisfy the product promise of OS-enforced per-application routing.

They may remain compatibility helpers but must not be represented as equivalent to WFP enforcement.

## 5. Recommended decision direction

Technical recommendation for Owner/Product Owner review: **Option A — Arvectum-owned narrow WFP ALE callout + privileged service + local proxy**, with an intentionally small kernel/native surface.

The recommendation is based on continuity with the completed APL-ROUTE-001..004 work and the fact that Windows already supplies the exact process-aware connect-redirection primitives the product needs. The current v0.2.10 safety baseline strengthens, rather than weakens, the case for a narrow ownership namespace and fail-closed recovery: the privileged plane must be able to prove what it owns before mutating or removing anything.

Recommended division of responsibility:

### Unprivileged control plane

- application selection and routing-rule editing;
- APL-ROUTE-001 validation/canonicalization;
- compile deterministic enforcement plan;
- display capability/health/recovery state;
- never receive arbitrary WFP administration authority.

### Privileged Windows service/native enforcement layer

- authenticated local IPC with a narrow versioned command schema;
- validate plan version/digest and allowed resource namespace;
- own WFP engine/provider/sublayer/callout/filter lifecycle;
- install only filters derived from validated Arvectum plans;
- drive APL-ROUTE-004 prepared/applied/restoring state transitions;
- expose deterministic health/reconcile/restore operations;
- refuse foreign-resource deletion and fail closed on corrupt ownership evidence.

### Local proxy service

- accept WFP-redirected connections;
- preserve/query WFP redirect records and context as required;
- reconstruct original destination safely;
- proxy through the selected SOCKS5/HTTP(S) upstream or perform explicitly allowed direct egress;
- mark/identify its own outbound sockets so they are not recursively redirected.

## 6. Kernel/native surface minimization

If Option A is approved, the native boundary should be deliberately smaller than the product feature set.

The callout should not know about UI concepts, subscriptions, proxy pools, business rules or arbitrary JSON. Its job should be limited to verified process/destination matching and safe redirection/permit behavior.

Complex policy compilation belongs in the testable user-mode control plane. The privileged service should receive a canonical, bounded plan and reject anything outside its schema/capability version.

## 7. Domain-routing boundary

Domain selectors cannot be truthfully enforced at the ALE IP-connect layer by resolving a domain once and pinning its current addresses.

Before enabling domain-aware per-app production rules, choose a separate architecture, for example:

- controlled DNS observation/cache with TTL-aware mappings and explicit ambiguity behavior;
- local DNS/proxy integration where the proxy receives hostname semantics from the application protocol;
- or mark domain-specific rules unsupported for protocols where hostname identity cannot be preserved reliably.

CIDR/all selectors can reach production before domain selectors if the capability model reports the distinction explicitly.

## 8. Required recovery invariants

Any approved implementation must preserve APL-ROUTE-004 and the current v0.2.10 saved-or-Arvectum safety contract, and prove at minimum:

1. journal written before first host mutation;
2. only `Arvectum.ProxyLauncher.*` resources created/removed;
3. GUI/service crash leaves enough durable state for deterministic reconciliation;
4. machine reboot while routing is active does not leave an unrecoverable or invisible policy;
5. corrupted/mismatched journal fails closed and does not start a second session;
6. uninstall/update cannot erase ownership evidence before WFP resources are verified absent/restored;
7. service/proxy outbound sockets cannot enter an infinite redirect loop;
8. coexistence with unrelated firewall, VPN, EDR and WFP providers does not trigger foreign cleanup;
9. detection of foreign/ambiguous enforcement state blocks destructive reconciliation and surfaces a recoverable diagnostic rather than silently adopting or deleting that state.

## 9. Security boundary

A production WFP enforcement service is a privileged security component. Therefore:

- IPC caller authentication/authorization must be explicit;
- arbitrary executable paths, filter conditions and raw WFP commands must not pass unchecked from GUI to privileged service;
- plan and binary provenance must be attributable;
- service/driver update must be signed and version-compatible;
- logging must avoid proxy credentials and unnecessary destination/privacy data;
- no remote control/listening interface is needed for the first production implementation;
- least privilege must be applied separately to GUI, service and proxy process.

## 10. Release/signing dependency

Production Option A depends on a trustworthy Windows signing/distribution path for the privileged service/callout and any required driver package.

This decision must therefore remain coordinated with APL-REL-016. The architecture may be approved before final certificate/provider procurement, but production release cannot claim completion until the exact driver/service signing requirements and clean-machine install behavior are proven. The current public `v0.2.10` release is immutable and is not eligible for retrofitted embedded signing or per-application enforcement; either change belongs to `v0.2.11+` or another later version after its own gates.

No current decision packet authorizes signing credentials, certificate purchase or release publication.

## 11. Physical Windows acceptance matrix

After explicit architecture approval and implementation, require a real supported Windows host matrix covering:

- selected browser through upstream SOCKS5 proxy while unselected app remains direct;
- inverse direct/proxy rules;
- multiple selected applications and priorities;
- IPv4 and IPv6;
- TCP plus supported UDP cases;
- proxy authentication failure/outage;
- application restart;
- proxy/service crash;
- GUI crash;
- service restart;
- Windows reboot while routing active;
- sleep/wake and network change;
- concurrent corporate VPN/WFP/Defender presence where practical;
- update/repair/uninstall;
- exact rollback to pre-session network state;
- proof that foreign firewall/WFP resources were unchanged;
- proxy-loop prevention;
- diagnostics/privacy review.

Domain selectors get a separate PASS gate only after their DNS lifecycle architecture exists.

## 12. Decision record required

Owner/Product Owner should explicitly choose one of:

- `APPROVE OPTION A — Arvectum-owned WFP callout/service/local-proxy enforcement`;
- `APPROVE OPTION B — third-party WFP/interception dependency`, naming the approved dependency and commercial/security conditions;
- `APPROVE OPTION C — virtual-adapter/TUN architecture`, accepting the broader routing scope;
- `REJECT / REQUEST MORE EVIDENCE`.

The decision should also state whether production scope initially includes only `all/CIDR` selectors or waits for domain-aware enforcement.

Until an explicit decision exists, no production enforcement architecture is approved and no privileged host mutation should be implemented as a production feature.
