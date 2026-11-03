# iOS 0.2.0 — automatic site-exclusion groups

## Product decision, 2026-11-03

- Default: automatic first-party dependency discovery/approval ON.
- Settings → “Автоматически расширять исключения”: switch ON/OFF. OFF still scans on explicit Add/Find, but new linked hosts are suggestions and require user selection. Switching OFF does not silently revoke prior approved hosts.
- Each manually entered site is a parent row with a disclosure group: built-in aliases, observed dependencies with state/evidence, and user-linked domains. The user can add arbitrary hostnames (e.g. an external identity provider), revoke/deny, or remove individual child entries. All are parent-scoped.
- A user denial survives network re-scans and TTL. Removing a child creates a bounded persistent suppression tombstone; manually adding it again clears the suppression. Removing the parent clears its whole group and tombstones.
- Only first-party same-root hosts independently seen in both HTML and resource timing can be automatically approved; known analytics/beacon/tracking labels and third-party/CDN hosts remain manual. Automatic authorisation does not expand to unrelated domains or arbitrary IP ranges.
- User-added links are explicit grants with local persistence, not WebKit/network heuristics. Their effect is still governed by existing iOS Packet Tunnel excluded-IP route limitations. Keep the existing 24 candidates per root, 32 effective exclusion rule budget and scoped validations.
- If an initial WebKit scan fails while the VPN still blocks a site, the scan error is non-fatal and must NOT prevent Save/Apply of the parent exception. Actual apply still follows the existing VPN reconnect/rollback safety contract.
- No Apple privacy label, RSYA SDK, advertisement, iPhone VPN, profiles, public App Store build or Apple review state is modified.

## Engineering and release limitation

Automatic parent/child grouping is NOT equivalent to automatically proving a safe independent DIRECT egress per hostname. Current consumer NEPacketTunnelProvider excludedRoutes acts by IP, potentially shared by unrelated CDN domains. The app's TLS-interface probe does not certify traffic outside the VPN. An authenticated Safari redirect can remain invisible to the initial WKWebView scan. Therefore **Smart3 zero-touch timeout → verified DIRECT → remembered exact-host route is NOT DONE**, and iOS 0.2.0 release remains gated on a supported safe architecture and physical egress/no-leak test. This implementation must not be described as that unimplemented behavior.

## QA acceptance

- New install/migration: auto-expansion defaults ON and persists setting; OFF causes no new automatic first-party approval.
- Add parent A: scanner starts, eligible children appear under A; weak first-party and third-party hosts remain suggestions.
- User links auth.partner.test under A: it appears in A only, survives Save/reopen and TTL, and disappears when A removed.
- Remove child: a rescan never automatically reintroduces it. Add again restores it.
- User rejection, malformed/oversized graph, 24/32 limits, TTL, www, multiple parents and backward-compatible JSON checked.
- If scan fails, the root must still be savable. No prior user profiles/VPN state touched.
- Run Swift core tests, relevant simulator UI tests, unsigned debug/release builds, then physical iPhone UX only with approved controlled setup. Full Smart3 Safari per-host independent route acceptance remains separately blocked.

Work branch: `feat/ios-020-auto-expansion-groups-20261103`; draft PR #302 targeting ongoing PR #296.
