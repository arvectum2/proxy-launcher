# APL-IP-002-MAC — macOS stack & dependency sovereignty audit

Status: **PASS / RELEASE-TRUST DEPENDENCY RECORDED**. APL-MAC-008 real-host functional acceptance and Gate R9 are closed; Apple Developer ID/notarization is now an explicit release-only external dependency.

## Inventory

| Component | Class | Provider/origin | Bundled | External network at runtime | Criticality / sovereignty note |
|---|---|---|---|---|---|
| frozen Python/Tk application | runtime | Python/PyInstaller ecosystem | yes | no | foreign build/runtime ecosystem; exact build versions locked |
| `/usr/sbin/networksetup` | host runtime | Apple/macOS | no | no | critical system-proxy control plane; cannot be replaced without changing platform architecture |
| LaunchAgents / plist format | host runtime interface | Apple/macOS | no | no | autostart only; per-user and non-privileged |
| `/usr/bin/hdiutil` | build/package | Apple/macOS | no | no | DMG build-only tool |
| `codesign` / Developer ID | release signing | Apple/macOS | no | no runtime dependency | production identity is held on an Arvectum-controlled Mac; public release promotion verifies Developer ID authority, team id and timestamp |
| GitHub macOS 15 arm64/x64 runners | CI/build | GitHub + Apple-hosted image ecosystem | no | no end-user dependency | cloud runners create unsigned/ad-hoc QA inputs; production trust is added only on the Arvectum-controlled signing Mac |
| Apple production notarization service | release promotion | Apple | no | yes during release only | active for macOS public production distribution; canonical Arvectum Release Bot credential stays local to the trusted signing Mac and is not a runtime dependency |

## Runtime autonomy

Normal proxy operation has no mandatory Arvectum cloud, Apple web API or third-party SaaS dependency. The product talks to local Apple system tooling and writes rollback/autostart state under the user's profile. The macOS platform itself is proprietary and foreign-controlled; therefore the task cannot claim full sovereign substitution of the operating-system control plane.

## Build sovereignty

The current CI path depends on GitHub-hosted macOS runners and PyPI acquisition of the frozen Python build set. The build scripts themselves are portable to an Arvectum-controlled physical Mac runner and do not require GitHub-specific APIs. A sovereign/restricted build perimeter can therefore mirror the pinned Python packages and run the same scripts locally.

## Findings

- **MAC-SOV-01 — P1:** macOS/Apple system tooling is intrinsically foreign platform infrastructure. This is accepted as a platform constraint, not hidden as an Arvectum-owned dependency.
- **MAC-SOV-02 — P1 build:** GitHub/PyPI remain build channels, but production trust is promoted on an Arvectum-controlled ephemeral self-hosted Mac runner; controlled mirrors remain the restricted-build fallback.
- **MAC-SOV-03 — ACTIVE RELEASE DEPENDENCY:** Apple production code signing/notarization introduces an online Apple-service dependency only at macOS release-promotion time. Ordinary installed runtime remains independent of Apple web APIs.
- **MAC-SOV-04 — PASS runtime autonomy:** no mandatory vendor SaaS is needed for ordinary proxy operation after installation.

## Acceptance

- [x] runtime/build/package/autostart dependencies classified;
- [x] bundled vs host-owned components separated;
- [x] external runtime/build network dependencies identified;
- [x] self-hosted build replacement path recorded;
- [x] Apple signing/notarization kept outside functional correctness claims while activated for release trust;
- [x] Arvectum-controlled ephemeral macOS production-signing perimeter implemented;
- [x] real macOS acceptance — APL-MAC-008.
