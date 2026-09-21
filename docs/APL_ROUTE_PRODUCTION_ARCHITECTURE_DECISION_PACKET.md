# APL-ROUTE — Windows production enforcement architecture decision packet

Status: `OWNER REVIEW REQUIRED / no production architecture approved`
Date: `2026-09-21`
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

### Current v0.2.12 safety baseline

The production decision is now evaluated against the published `v0.2.12` desktop baseline. `v0.2.12` is an immutable patch release from exact green main and preserves the saved-or-Arvectum rollback-safety contract established in `v0.2.9`; its product changes are long-sleep recovery fixes, not broader Windows host-mutation authority. Windows, Astra/Fly and RED OS/KDE therefore continue to share the same ownership rule: if the host presents a third/foreign proxy state, Proxy Launcher fails closed and preserves durable rollback evidence instead of overwriting that state. Any future per-application enforcement plane must preserve that invariant rather than introducing broader privileged cleanup authority.

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

## 4. Architecture options

### Option A — Arvectum-owned WFP ALE callout + narrow Windows service + local proxy

Shape: `GUI/control plane -> authenticated local IPC -> privileged Arvectum service/callout -> WFP ALE connect redirect -> local proxy -> upstream proxy/direct target`.

Advantages: native process identity, deterministic Arvectum ownership/cleanup, continuity with APL-ROUTE-001..004, and no need to replace the whole Windows network stack.

Costs/risks: privileged native surface, signing/update/uninstall burden, TCP/UDP/IPv4/IPv6 and coexistence testing, and a separate DNS lifecycle problem for domain selectors.

### Option B — third-party WFP/redirect driver or interception SDK

May reduce custom kernel engineering, but introduces a material privileged dependency with sovereignty, licensing, SBOM, vulnerability-response, supply-chain and commercial implications. Any paid/material dependency requires explicit Owner approval.

### Option C — full virtual adapter/TUN/VPN enforcement

Offers broad packet visibility but materially increases blast radius and still needs reliable Windows process attribution. DNS, route ownership, coexistence with corporate VPNs/filter drivers and recovery become more complex than the current selected-app requirement needs.

### Option D — system proxy/PAC/environment/process configuration tricks

Not suitable as production enforcement because applications can bypass them and PAC is destination-oriented rather than strong process enforcement. They may remain compatibility helpers only.

## 5. Recommended decision direction

Technical recommendation for Owner/Product Owner review: **Option A — Arvectum-owned narrow WFP ALE callout + privileged service + local proxy**, with an intentionally small native surface.

The recommendation is not approval. It follows the completed APL-ROUTE-001..004 control-plane work and preserves the current v0.2.12 ownership/fail-closed recovery model.

Recommended responsibility split:

- unprivileged control plane: application/rule UX, validation/canonicalization, deterministic plan compilation, capability/health/recovery display;
- privileged service/native enforcement: authenticated local IPC, bounded schema, WFP provider/sublayer/callout/filter lifecycle, ownership journal transitions, health/reconcile/restore, refusal to delete foreign resources;
- local proxy: accept redirected connections, preserve redirect context, recover original destination safely, use selected upstream/direct egress, prevent redirect loops.

## 6. Domain-routing boundary

Domain selectors cannot be truthfully enforced at ALE IP-connect by resolving a domain once and pinning current addresses. Before domain-aware production rules, choose a TTL-aware DNS observation/cache or hostname-preserving proxy integration, or report the capability unsupported where hostname identity cannot be preserved reliably. CIDR/all selectors can reach production first if the capability model reports the distinction explicitly.

## 7. Required recovery invariants

Any approved implementation must prove at minimum:

1. journal before first host mutation;
2. only `Arvectum.ProxyLauncher.*` resources created/removed;
3. deterministic crash/reboot reconciliation;
4. corrupted/mismatched journal fails closed;
5. update/uninstall cannot erase ownership evidence before owned resources are verified absent/restored;
6. proxy/service outbound sockets cannot enter redirect loops;
7. unrelated firewall/VPN/EDR/WFP providers are never adopted or deleted;
8. foreign/ambiguous enforcement state blocks destructive reconciliation and surfaces a recoverable diagnostic.

## 8. Security and release boundary

A production WFP service/callout is a privileged security component. IPC authentication/authorization, bounded plan validation, least privilege, privacy-safe logging, binary/plan provenance and signed/version-compatible update behavior are mandatory. No remote-control listener is needed for the first production slice.

Production Option A must remain coordinated with APL-REL-016. Architecture may be approved before certificate/provider procurement, but production release cannot complete until exact driver/service signing requirements and clean-machine install behavior are proven. Published `v0.2.12` is immutable; any embedded signing or per-app enforcement belongs to a new version after `v0.2.12`.

## 9. Physical Windows acceptance matrix after approval

Require a real supported Windows host matrix covering selected/unselected app routing, inverse direct/proxy rules, multiple applications/priorities, IPv4/IPv6, supported TCP/UDP, authentication/outage, app/service/proxy/GUI restart/crash, reboot, sleep/wake/network change, coexistence with VPN/WFP/Defender where practical, update/repair/uninstall, exact rollback, foreign-resource preservation, loop prevention and diagnostics/privacy. Domain selectors get a separate PASS only after their DNS lifecycle architecture exists.

## 10. Decision record required

Owner/Product Owner should explicitly choose one of:

- `APPROVE OPTION A — Arvectum-owned WFP callout/service/local-proxy enforcement`;
- `APPROVE OPTION B — third-party WFP/interception dependency`, naming dependency and conditions;
- `APPROVE OPTION C — virtual-adapter/TUN architecture`, accepting broader routing scope;
- `REJECT / REQUEST MORE EVIDENCE`.

The decision should also state whether initial production scope is only `all/CIDR` selectors or waits for domain-aware enforcement.

Until an explicit decision exists, no production enforcement architecture is approved and no privileged host mutation should be implemented as a production feature.
