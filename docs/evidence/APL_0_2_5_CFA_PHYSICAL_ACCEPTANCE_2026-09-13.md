# Arvectum Proxy Launcher 0.2.5 — CFA physical acceptance closure

Status: **PASS / CLOSED FOR THE EXACT TESTED SETUP**

The `0.2.5` CFA hotfix was physically accepted on the owner-operated Windows host with Windows Defender Controlled Folder Access enabled. The accepted product source remains commit `9e8ca7e851563082cd7d03d7543ccb360a37ec27`; this evidence record does not change the accepted product bytes.

## Exact accepted identities

| Item | Accepted identity |
| --- | --- |
| Product version | `0.2.5` |
| Accepted product source commit | `9e8ca7e851563082cd7d03d7543ccb360a37ec27` |
| GitHub Actions Windows-installer run | `34720855917` |
| Windows-installer artifact ID | `10306540886` |
| Windows-installer artifact ZIP SHA-256 | `a9c973b68bfd58ff7c16afedb0d13edf98173ab0d690e189580e6f45327362ec` |
| Accepted Setup SHA-256 | `9b5368d67874b7164ee56a245c75db4b23af593a1d72f7e947774516abcc95e3` |
| Accepted installed application SHA-256 | `1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c` |
| Canonical install path | `%LOCALAPPDATA%\Programs\ArvectumProxyLauncher\Arvectum Proxy Launcher.exe` |
| Raw physical evidence SHA-256 | `2afe6af76a69dc4d0b6869385dda6c4467c3d01e38997a04ca554c28aa24021a` |
| Raw physical evidence schema | `arvectum.proxy.0.2.5.final-physical-reboot.v1` |

The exact raw physical JSON was produced at `2026-09-13T01:48:14.7339704+03:00` after a clean reboot whose recorded boot time was `2026-09-13T01:45:22.5000000+03:00`.

## What was physically proved

The accepted Setup was installed while the pre-existing proxy runtime was live and Controlled Folder Access was enabled. The late transactional handover completed successfully without a CFA block. The resulting application was the exact `0.2.5` EXE above in the LocalAppData Programs path.

A subsequent clean reboot test proved all of the following against those accepted bytes:

- `0.2.5` executable exists at the canonical LocalAppData Programs path;
- executable SHA-256 is exactly `1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c`;
- canonical `HKCU\...\Run\ArvectumProxyLauncher` points to the installed `0.2.5` EXE with `--start`;
- exactly one process owns TCP `127.0.0.1:8082`;
- that process is the canonical installed `0.2.5` EXE;
- `http://127.0.0.1:8082/proxy.pac` returns HTTP `200`;
- real HTTPS traffic to `https://example.com/` succeeds through local proxy `http://127.0.0.1:8080`;
- the legacy Python `0.2.3` runtime is absent after clean reboot.

The raw result records every final check as `true` and `result = PASS`.

## Legacy developer-autostart boundary

Before the final reboot acceptance, this development host still had a historical non-production Run value:

`"C:\P0_2_RECOVERY\Python312\pythonw.exe" "C:\Opencode projects\proxy-launcher\proxy_core.py" --start`

The production code deliberately refused to overwrite that Python command because it is not provably owned by the strict production EXE-command classifier. That fail-closed ownership rule is retained. On this known development host only, the value was manually migrated after exact validation to the canonical installed `0.2.5` command.

The old Desktop shortcut was also proven to target the known `P0_2_RECOVERY` Python GUI and was removed only after the final canonical runtime checks passed. No product code was weakened to treat arbitrary Python commands as owned.

## Reboot incident interpretation

The first reboot observation initially appeared to show a `0.2.5` autostart failure. Diagnostics proved the opposite: `0.2.5` had started automatically and enabled the proxy. The operator then clicked the historical Desktop shortcut, which launched the old `0.2.3` Python GUI/runtime and took over port `8082`. A second clean reboot with no legacy shortcut launch produced the authoritative PASS result recorded above.

## CI linkage

The exact Setup used for physical acceptance came from Windows-installer run `34720855917`. That run passed:

- exact product/version checks;
- issue `#171` CFA-safe installer regression;
- fresh/install/upgrade/repair/uninstall Windows RC lifecycle;
- Gate R6 packaging acceptance.

The run's RC evidence also records the exact application SHA-256 `1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c` and Setup SHA-256 `9b5368d67874b7164ee56a245c75db4b23af593a1d72f7e947774516abcc95e3`.

## Release-set boundary

This closure proves the exact Setup/application CFA and reboot behavior. It does **not** by itself authorize publication or claim that a separately rebuilt portable ZIP is byte-identical to the application accepted here.

The same Windows-installer run recorded a portable ZIP SHA-256 of `7e65d980b376977b33263a7b7ad97ade9c3c83f3eb685c5ab624ce342fb71af0`, but that run did not retain the portable ZIP itself in its uploaded installer artifact. A later independent portable build at the same source commit produced different PyInstaller application bytes, so it must not be substituted silently for the physically accepted application.

Therefore the production release ceremony must first materialize a portable release package around the **exact accepted application bytes** or perform a new exact-byte acceptance of any replacement portable/application build. A version label or same source commit is insufficient.

## Closure decision

The `0.2.5` CFA hotfix physical gate is **PASS / CLOSED** for:

- accepted Setup `9b5368d6…95e3`;
- accepted application `1ab36b7a…653c`;
- LocalAppData install target;
- active-runtime upgrade under CFA;
- canonical autostart;
- clean reboot recovery;
- PAC availability;
- real HTTPS-through-proxy connectivity;
- absence of the legacy Python runtime after clean reboot.

Publication remains governed separately by the Russia-first REL-011/REL-012/REL-013 signed-release chain and by an exact release-set contract for `0.2.5`.