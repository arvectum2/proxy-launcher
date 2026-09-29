# APL-ROUTE-005 — Windows production per-app routing foundation

Status: **IN PROGRESS — Option A approved, control/service boundary implemented, live WFP enforcement not yet accepted.**

Owner decision on 2026-09-29 selected Option A from PR #144:
Arvectum-owned WFP ALE connect-redirection callout + narrow privileged Windows service + local proxy.

## Production scope v1

- application identity: WFP application id derived from executable path;
- actions: redirect to Arvectum local proxy or bypass Arvectum redirect;
- destinations: all traffic or canonical IPv4/IPv6 CIDR;
- domain selectors: rejected fail-closed until a DNS-aware address lifecycle exists;
- maximum service plan: 512 filters;
- no arbitrary firewall/service/registry commands are present in the control protocol.
## Implemented foundation

- `windows_routing_service_contract.py` defines the bounded protocol and fixed Arvectum-owned resources.
- `windows_routing_controller.py` persists the ownership journal before any service request, verifies exact resource acknowledgement and preserves restoring evidence after failed apply.
- restoration clears durable evidence only after the service confirms the exact owned resource set was removed and no owned resources remain.
- local named-pipe transport is Windows-only and limits request/response frames to 1 MiB.
- `native/windows_routing/wfp_sdk_probe.cpp` verifies the native Windows SDK/WFP user-mode surface without host mutation.
- dedicated Windows CI compiles/runs the native SDK probe and executes routing contract/recovery tests.

## Safety boundary

The implementation still reports `live_enforcement_supported=false`.
This is intentional: the kernel callout/service enforcement plane has not yet been built, installed and accepted on a real Windows host.
No CI or non-Windows test may relabel that missing physical proof as PASS.
## Next native slice

1. implement and build the signed-capable WFP callout driver;
2. implement the narrow Windows service that owns provider/sublayer/callout/filter lifecycle and authenticated local IPC;
3. connect the service to the existing local proxy with original-destination/redirect-context handling;
4. prove self-redirect loop prevention;
5. run selected vs unselected app routing, crash/reboot/repair/uninstall and foreign-resource preservation on a real supported Windows host;
6. only then switch Windows application-routing capability to supported.

Microsoft's connect-redirection contract requires querying redirect state, using a redirect handle for local proxying, and avoiding re-redirection of flows previously redirected by the same callout.
