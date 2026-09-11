# APL-WIN-014 — final physical acceptance closure

Status: **PASS / CLOSED**

Physical acceptance completed on dedicated host `ARVECTUM-DEMO` under enforced Windows App Control for Business. The accepted product candidate remains the immutable source commit `e2278dbbd99b0d98ba9e4f836e40b2d60ea94b30`; this documentation-only closure does not change the accepted product bytes.

## Scope

APL-WIN-014 proves the exact-byte Windows lifecycle for the final `0.2.4` candidate from an exact sealed `0.2.3` predecessor under enforced App Control:

- exact predecessor identity;
- real `0.2.3 -> 0.2.4` upgrade;
- exact installed candidate identity;
- PyInstaller one-file native runtime under exact-hash supplemental trust;
- PAC listener and WinINET `AutoConfigURL` establishment;
- rollback;
- repair;
- uninstall;
- zero Arvectum-related Code Integrity event `3077` blocks;
- base and candidate supplemental policies remaining enforced after the lifecycle.

## Accepted identities

| Item | Accepted identity |
| --- | --- |
| Candidate source commit | `e2278dbbd99b0d98ba9e4f836e40b2d60ea94b30` |
| Candidate ZIP SHA-256 | `467864f286dc4c4de6c0f6033ae5cd5420a691c1bc9a32bf4891285c8c1d29bf` |
| Candidate Setup SHA-256 | `28eb0b06c2f478b46d5845c6bb1970c96e20a2f6fdaf1d48501ed69f52ea6965` |
| Candidate application SHA-256 | `0415226f882e16a0ce370b766c4c68d3c23861f97361da093a1fd9d9f0e0832c` |
| Predecessor Setup SHA-256 | `5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414` |
| Predecessor application SHA-256 | `f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a` |
| Base App Control PolicyID | `dc1c604c-46ea-40b7-9f47-cf582b225d5e` |
| R2 supplemental PolicyID | `8DB17F98-FBD9-42C4-B37F-FCF3BF6959C7` |
| R2 supplemental CIP SHA-256 | `949E6858338FD3FC8969A18B454095C863E7AB44F52A5C120327098FD590BD1A` |

The final candidate kit contained `1023/1023` verified checksum-manifest entries, including `1005` exact PyInstaller native runtime binaries (`31,141,126` bytes total). Candidate-derived Inno runtime and PyInstaller native runtime were both part of the exact-hash trust surface; no broad `%TEMP%`, publisher, or directory allow rule was used.

## Authoritative physical result

Physical run window: `2026-09-11T22:12:07.7235319Z` through `2026-09-11T22:12:53.3618076Z`.

| Gate | Result |
| --- | --- |
| Overall | **PASS** |
| App Control before | PASS |
| Predecessor | PASS |
| Upgrade | PASS |
| Runtime | PASS |
| Rollback | PASS |
| Repair | PASS |
| Uninstall | PASS |
| App Control after | PASS |
| Code Integrity 3077 | PASS |
| Code Integrity 3077 count | `0` |

Runtime evidence recorded listener PID `4496`, starter PID `12548`, PAC HTTP status `200`, PAC body length `5591`, and exact WinINET `AutoConfigURL = http://127.0.0.1:8082/proxy.pac`.

The authoritative physical result is preserved on the stand at:

`C:\Arvectum\Evidence\APL-WIN-014\final-0.2.4-e2278db-r2\apl-win-014-final-0.2.4-physical-result.json`

Supporting evidence directories:

- physical evidence: `C:\Arvectum\Evidence\APL-WIN-014\final-0.2.4-e2278db-r2`;
- policy evidence: `C:\Arvectum\Evidence\APL-WIN-014\final-0.2.4-policy-e2278db-r2`;
- predecessor evidence: `C:\Arvectum\Evidence\APL-WIN-014\predecessor-0.2.3-e2278db-r2`.

## Acceptance fixture boundary

The first physical attempt against the same candidate was retained as BLOCK evidence. It showed that the product correctly refused `--start` when no upstream proxy was configured; the product log recorded `proxy.start_aborted` / `start aborted: no upstream proxy configured`, with no relevant Code Integrity block in that run.

R2 therefore used a temporary non-credential acceptance fixture with upstream `127.0.0.1:9` solely to exercise the local runtime, PAC, WinINET and lifecycle mechanics that are in scope for APL-WIN-014. The fixture SHA-256 was `83C20F8428CF119BC777C1F64DDC5A80255A5AEFDFCC39596ABFB401E4C6344A`. It contained no credentials and was removed after the successful run. This fixture does **not** claim external upstream reachability or authentication proof; those are outside this gate.

R1 evidence was not modified.

## Closure decision

APL-WIN-014 is **DONE**. The physical App Control gate is closed for the exact `0.2.4` candidate identified above.

This closure does not by itself activate embedded production code signing, complete human/legal IP approval, complete APL-REL-014, create or move a public release tag, or publish a stable GitHub Release. Those remain governed by their separate release/legal gates.

Preserve the accepted candidate material, R2 policy authoring directory, R2 physical evidence directory, predecessor evidence, and the active R2 supplemental policy until deliberate post-acceptance cleanup is separately authorized.