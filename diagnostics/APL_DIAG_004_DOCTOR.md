# APL-DIAG-004 — Doctor / automated self-diagnostics

**Status:** IMPLEMENTED
**Depends on:** APL-DIAG-001 Structured logging, APL-DIAG-002 Secret redaction, APL-DIAG-003 Windows diagnostics collector
**Report schema:** `arvectum.proxy.doctor.v1`

## Goal

Turn the read-only APL-DIAG-003 snapshot into an actionable automated health assessment that can be used by a customer, support engineer, GUI, script, or CI without changing Windows network state.

Doctor is intentionally separate from the support-bundle collector. APL-DIAG-003 gathers evidence; APL-DIAG-004 evaluates that evidence.

## Safety boundary

Doctor itself:

- performs no external network requests;
- does not enable/disable WinINET proxy or PAC;
- does not start/stop the proxy engine;
- does not modify recovery backups or migration state;
- does not create/delete autostart entries;
- does not clear an orphaned PAC automatically;
- does not generate a support ZIP automatically;
- only asks APL-DIAG-003 for its in-memory redacted snapshot;
- forces APL-DIAG-003 settings reads into non-migrating mode, so legacy plaintext credentials are not rewritten to DPAPI merely because Doctor inspected them;
- applies APL-DIAG-002 redaction to the final report again as defense in depth.

The only artifact Doctor explicitly creates is an explicitly requested JSON report path (`--output`); it is written atomically and does not alter application/network state. Existing read helpers may still append an error to the ordinary structured log if Windows itself rejects a diagnostic read.

## Stable result model

Every run returns:

- `schema = arvectum.proxy.doctor.v1`;
- `overall = PASS | WARN | FAIL`;
- `exit_code = 0 | 1 | 2` respectively;
- deterministic check IDs;
- per-check status and concise reason;
- remediation for actionable WARN/FAIL conditions;
- summary counts and de-duplicated recommended actions.

Exit codes are deliberately non-binary so automation can distinguish a usable-but-needs-attention state from a hard failure.

## Checks

Doctor v1 evaluates:

1. `collector.integrity` — the input schema must match APL-DIAG-003 and all expected sections must exist; schema mismatch or failure of an essential state source is FAIL, optional evidence loss is WARN.
2. `redaction.self_test` — synthetic credentials must be removed while the proxy endpoint remains diagnostically useful.
3. `platform.windows` / `platform.macos` / `platform.linux` — the current supported desktop platform must be identified without treating another supported OS as a failure.
4. `configuration.ports` — HTTP/SOCKS5/PAC ports must be valid and distinct.
5. `configuration.upstream` — at least one usable upstream host/port should be configured; absence is WARN, malformed port is FAIL.
6. `state.migration` — blocked runtime-state migration is FAIL.
7. `state.recovery` — rollback backups are normal while the engine is running; the same pending-backup state with the engine stopped means interrupted recovery and is FAIL.
8. `state.engine_proxy` — engine and system proxy/PAC state must be consistent.
9. `state.pac_ownership` — stale/unowned or orphaned Arvectum PAC state is FAIL; Doctor never deletes it automatically.
10. `listeners.health` — when the engine is running, all localhost listeners and PAC protocol must be healthy; when stopped, occupied configured ports are WARN. On macOS, Doctor performs a best-effort read-only `lsof` lookup so the warning can name the conflicting port/process and point to editable local listener ports.
11. `recovery.autostart` — unreadable/stale/unowned recovery-autostart state is surfaced as a warning where safe; foreign entries are never deleted or overwritten.

## CLI

Source/console mode:

```text
python doctor.py
python doctor.py --json
python doctor.py --json --output C:\path\to\doctor.json
```

Packaged Launcher routing:

```text
ArvectumProxyLauncher.exe --doctor
ArvectumProxyLauncher.exe --doctor-json
ArvectumProxyLauncher.exe --doctor-json C:\path\to\doctor.json
```

`--doctor` is evaluated before portable self-handoff so its exit code belongs to the exact executable being diagnosed. `--doctor-json PATH` is useful for support/automation even for a windowed PyInstaller build where `sys.stdout` may be unavailable; explicit JSON output therefore never depends on a console handle.

## GUI

The Windows GUI exposes a `Диагностика` service button. Doctor runs in a background thread so local CIM/listener collection cannot freeze Tk. The GUI reports PASS/WARN/FAIL and recommended action IDs; it does not silently repair network state.

## Acceptance criteria

- [x] Reuse the APL-DIAG-003 in-memory snapshot rather than duplicating Windows collection logic.
- [x] No external connectivity requirement and no configuration/network/recovery mutation; settings collection uses non-migrating reads.
- [x] Stable PASS/WARN/FAIL statuses and exit codes 0/1/2.
- [x] Distinguish normal active-session rollback backups from interrupted recovery, and detect migration conflict, stale/orphaned PAC and engine/PAC inconsistency.
- [x] Validate configured local ports and upstream endpoint structure.
- [x] Validate required localhost listeners when the engine is running and surface port occupation when stopped.
- [x] Run a synthetic APL-DIAG-002 redaction self-test.
- [x] Re-redact every final report as defense in depth.
- [x] Expose human-readable and JSON CLI modes.
- [x] Support atomic explicit JSON output.
- [x] Integrate Doctor into the Windows GUI without blocking Tk.
- [x] Unit-test healthy, warning, recovery-failure, state-inconsistency, port, collector, redaction, platform, CLI and JSON-output contracts.
- [x] Run dedicated tests on Ubuntu and Windows plus a native Windows Doctor smoke in GitHub Actions.
- [x] Compile Doctor dependencies in the canonical clean build and smoke-test `--doctor-json PATH` against the packaged Windows EXE.
