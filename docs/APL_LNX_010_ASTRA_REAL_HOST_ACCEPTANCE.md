# APL-LNX-010 — Astra Linux real-host acceptance

Status: **READY FOR REAL-HOST RUN — Gate R8 PENDING**

APL-LNX-009 proves the Linux packaging/runtime contract on Ubuntu CI. It does **not** close this gate. APL-LNX-010 closes only from PASS evidence produced on a real physical Astra Linux host in a normal interactive graphical session.

Canonical target for this roadmap:

- Astra Linux Special Edition 1.8;
- x86-64 / AMD64;
- Fly graphical desktop/session;
- NetworkManager managing the tested primary connection;
- exact governed `.deb` release candidate.

A VM, container, GitHub Actions runner, mock NetworkManager, or `--allow-non-astra` preflight may be used to develop the tooling, but can never be acceptance evidence for Gate R8.

## Purpose

Prove on the real Astra target that the current Linux product line safely supports:

- `.deb` install, update and remove lifecycle;
- interactive GUI startup and Linux/Astra runtime selection;
- NetworkManager capability/preflight behavior;
- PolicyKit/authorization UX where authorization is required;
- real enable, sync and disable;
- exact restoration of pre-existing NetworkManager proxy state;
- per-user autostart/login behavior;
- crash/relaunch and reboot/login recovery;
- user-state preservation across package lifecycle operations;
- bounded diagnostics/support evidence without credentials or raw local proxy configuration.

## Safety invariants

1. Capture the exact pre-test NetworkManager state before the first mutation.
2. Never delete `linux_proxy_backup.json` while rollback is pending.
3. Never use a generic proxy reset as a substitute for the product-owned rollback path.
4. If a foreign/newer proxy change causes the backend to refuse rollback, stop. Preserve evidence; do not overwrite the foreign state to manufacture PASS.
5. Do not restart NetworkManager or cycle interfaces as an acceptance shortcut.
6. Run the product from the normal logged-in graphical user session. Do not accept an SSH/headless-only result.
7. Keep raw screenshots, logs and support bundles private if they may contain usernames, local paths, connection names or customer network details.
8. `RESULT: PASS` is forbidden unless final network state has been mechanically compared to the captured baseline and no rollback remains pending.

## Acceptance tooling

Repository-owned tooling:

- `qa/collect_astra_acceptance_preflight.sh` — stable entry point;
- `qa/collect_astra_acceptance_preflight.py` — strict read-only host/candidate collector;
- `qa/collect_astra_network_state.py` — privacy-preserving NetworkManager snapshot;
- `qa/compare_astra_network_state.py` — exact proxy-state comparator;
- `qa/verify_astra_acceptance_bundle.py` — fail-closed final evidence verifier.

The NetworkManager collector does not store raw connection UUIDs, PAC URLs or PAC scripts. Those values are represented by SHA-256 identities so exact rollback can be checked without committing local network configuration.

## Private evidence directory

Create the evidence outside tracked source files:

```bash
EVIDENCE="$HOME/APL-LNX-010-$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 "$EVIDENCE"
export EVIDENCE
```

Required final files:

```text
00-repository.txt
01-preflight.txt
02-network-before.json
03-package.txt
04-gui.md
05-enable.md
06-network-enabled.json
07-disable.md
08-network-after-disable.json
09-autostart.md
10-crash-recovery.md
11-network-after-crash-recovery.json
12-reboot-recovery.md
13-network-after-reboot-recovery.json
14-update-remove.md
15-diagnostics-privacy.md
HOST_ATTESTATION.env
SUMMARY.md
```

Additional screenshots/logs/support bundles may be retained privately.

## Phase 0 — freeze source and candidate

Start from a clean checkout of the exact candidate source:

```bash
{
  git status --short
  git rev-parse HEAD
  git log -1 --oneline
  python3 --version
} > "$EVIDENCE/00-repository.txt"
```

Run at minimum:

```bash
python3 -m unittest \
  tests.test_astra_real_host_acceptance_tooling \
  tests.test_linux_backend \
  tests.test_linux_networkmanager_preflight \
  tests.test_linux_policykit_ux \
  tests.test_linux_runtime \
  tests.test_linux_runtime_preflight_wiring \
  tests.test_linux_autostart \
  tests.test_linux_diagnostics
```

For a final release candidate, run the full repository suite as well. No failing deterministic test may be waived to obtain real-host PASS.

Set the exact `.deb` candidate:

```bash
CANDIDATE=/absolute/path/to/arvectum-proxy-launcher_VERSION_amd64.deb
```

## Phase 1 — strict read-only preflight and baseline

Before installing or changing proxy state:

```bash
bash qa/collect_astra_acceptance_preflight.sh \
  "$EVIDENCE/01-preflight.txt" "$CANDIDATE"

python3 qa/collect_astra_network_state.py \
  "$EVIDENCE/02-network-before.json"
```

PASS requires all of the following:

- Astra Linux detected without `--allow-non-astra`;
- x86-64 host;
- not CI/container/known VM acceptance;
- real graphical login session available;
- `nmcli` available;
- at least one supported active NetworkManager connection;
- candidate SHA-256 and Debian package identity recorded;
- baseline snapshot succeeds before any product-owned mutation;
- no unexplained pre-existing pending Arvectum rollback state.

Create an explicit operator attestation after physically confirming the machine/session:

```bash
cat > "$EVIDENCE/HOST_ATTESTATION.env" <<'EOF'
physical_host=YES
interactive_graphical_session=YES
operator_confirmed=YES
EOF
chmod 600 "$EVIDENCE/HOST_ATTESTATION.env"
```

Do not create this file truthfully unless those conditions are actually met.

## Phase 2 — `.deb` lifecycle and GUI

Record the exact candidate and install evidence in `03-package.txt`, including the candidate SHA-256 from preflight.

Typical inspection/install commands are:

```bash
sha256sum "$CANDIDATE"
dpkg-deb -f "$CANDIDATE" Package Version Architecture Depends
sudo apt install "$CANDIDATE"
dpkg-query -W arvectum-proxy-launcher
```

Launch through the installed desktop entry or canonical launcher from the interactive Fly session. Record observations in `04-gui.md`.

PASS requires:

- package identity/version/architecture match the governed candidate;
- expected payload is installed;
- GUI opens without immediate crash;
- Linux/Astra backend is selected, not a Windows/macOS path;
- unavailable NetworkManager/authorization conditions fail truthfully rather than reporting success.

Package update/remove are completed in Phase 9 after state-preservation evidence exists.

## Phase 3 — NetworkManager capability and authorization UX

Exercise the product's real NetworkManager preflight from the GUI/session and record the result in `05-enable.md`.

Where the host policy requires authorization, exercise the normal PolicyKit path. PASS means the user sees a normal authorization flow and cancellation/denial is handled without partial mutation or false success. Do not run the whole application permanently as root to bypass this check.

Immediately before real enable, ensure `02-network-before.json` exists and that no previous rollback is pending.

Enable with an approved test upstream proxy configuration. Do not copy proxy credentials into evidence.

Then capture:

```bash
python3 qa/collect_astra_network_state.py \
  "$EVIDENCE/06-network-enabled.json"
```

PASS requires:

- product-owned proxy state is observable on supported active NetworkManager profiles;
- VPN/loopback profiles are not taken over by this backend contract;
- durable rollback evidence existed before first mutation;
- connection test follows the intended route when the approved upstream proxy is available;
- mutation/auth failure does not leave unexplained partial state.

## Phase 4 — sync/no-proxy ownership

Exercise one harmless no-proxy edit through the normal UI, for example an acceptance-only `.invalid` host, and restore the user's original value before final cleanup.

PASS requires sync to preserve the owned PAC identity and not replace the original rollback baseline. Current Linux backend ownership semantics intentionally update the product configuration identity without turning no-proxy sync into an unrelated NetworkManager reset.

Record the observation in `05-enable.md`.

## Phase 5 — normal disable and exact rollback

Disable through the normal product path, then collect and compare:

```bash
python3 qa/collect_astra_network_state.py \
  "$EVIDENCE/08-network-after-disable.json"

python3 qa/compare_astra_network_state.py \
  "$EVIDENCE/02-network-before.json" \
  "$EVIDENCE/08-network-after-disable.json" \
  | tee "$EVIDENCE/07-disable.md"
```

Comparator exit code 0 is mandatory. PASS also requires product-owned rollback evidence to be removed only after successful restoration.

If an independently introduced foreign proxy change makes the backend refuse rollback, that safety behavior is correct, but this phase is not PASS until the operator deliberately returns the test stand to a known safe baseline and repeats the acceptance case.

## Phase 6 — autostart and real login

Enable autostart through the product UI and verify the canonical per-user startup mechanism created by the Linux implementation. Log out/in (or combine with the reboot phase) and prove the application launches once in the graphical user session.

Record evidence in `09-autostart.md`.

PASS requires:

- per-user ownership rather than a surprise system-wide root service;
- no duplicate application instance;
- disabling autostart removes only the product-owned startup item;
- toggling autostart does not mutate proxy state by itself.

## Phase 7 — crash/relaunch recovery

From the clean baseline, enable normally and confirm rollback evidence exists. Terminate the product process without its normal disable path, then relaunch from the interactive session.

Recover/disable through the product, collect and compare:

```bash
python3 qa/collect_astra_network_state.py \
  "$EVIDENCE/11-network-after-crash-recovery.json"
python3 qa/compare_astra_network_state.py \
  "$EVIDENCE/02-network-before.json" \
  "$EVIDENCE/11-network-after-crash-recovery.json"
```

Record behavior in `10-crash-recovery.md`.

PASS requires pending recovery to remain detectable after the crash, exact baseline restoration, and rollback evidence cleanup only after successful recovery.

## Phase 8 — reboot/login recovery

With autostart enabled, start again from the proven baseline, enable the proxy, confirm durable rollback evidence, and reboot Astra normally while product-owned proxy state is active.

After graphical login:

- prove the expected autostart behavior;
- prove pending rollback is still detectable;
- recover/disable through the product;
- capture and compare:

```bash
python3 qa/collect_astra_network_state.py \
  "$EVIDENCE/13-network-after-reboot-recovery.json"
python3 qa/compare_astra_network_state.py \
  "$EVIDENCE/02-network-before.json" \
  "$EVIDENCE/13-network-after-reboot-recovery.json"
```

Record observations in `12-reboot-recovery.md`.

Exact comparator PASS is mandatory.

## Phase 9 — update/remove and user-state preservation

Perform lifecycle testing only while proxy state is clean and no rollback is pending.

Verify:

1. update/reinstall the governed package without destroying user settings/no-proxy configuration;
2. application still starts after update;
3. remove the package while clean;
4. package removal does not masquerade as rollback and does not erase user-owned state unexpectedly;
5. reinstall, if needed for final diagnostics, restores the application without corrupting preserved user state.

Record exact commands/results in `14-update-remove.md`.

Do not remove the application while an owned proxy/rollback is active as a way to satisfy cleanup.

## Phase 10 — diagnostics/support privacy

Generate the real implemented Linux diagnostics/support output from the normal product path and inspect it manually before sharing. Record the review in `15-diagnostics-privacy.md`.

PASS requires no proxy password/token/credential, no environment dump, no browser history, no arbitrary home-directory listing, and no raw rollback payload or other unnecessary local-network secret.

## Final cleanup

Before declaring PASS:

- restore the user's original no-proxy values;
- restore the intended autostart setting;
- stop the product proxy unless the stand owner explicitly wants it active after acceptance;
- prove current NetworkManager proxy state equals `02-network-before.json`;
- prove no unwanted `linux_proxy_backup.json` remains pending;
- verify normal connectivity and Astra GUI session remain healthy.

## `SUMMARY.md` contract

The final summary must use this structure; every listed line is mechanically checked:

```text
APL-LNX-010 — REAL ASTRA LINUX ACCEPTANCE
RESULT: PASS

SOURCE:
- repository: arvectum2/proxy-launcher
- branch/ref: ...
- commit SHA: ...
- product version: ...

HOST:
- Astra Linux version: ...
- architecture: x86_64
- physical host: YES
- interactive graphical session: YES

PACKAGE:
- candidate: ...
- candidate SHA256: ...

ACCEPTANCE:
- read-only preflight: PASS
- package install/remove/update: PASS
- GUI launch/platform UX: PASS
- NetworkManager runtime/preflight: PASS
- PolicyKit authorization UX: PASS
- real enable: PASS
- normal disable exact rollback: PASS
- autostart/login: PASS
- crash/relaunch recovery: PASS
- reboot/login recovery: PASS
- update/remove + user-state preservation: PASS
- diagnostics privacy: PASS
- final cleanup: PASS

pending rollback: NO
final proxy state: BASELINE
```

Finally run:

```bash
python3 qa/verify_astra_acceptance_bundle.py "$EVIDENCE"
```

`APL-LNX-010 VERDICT: EVIDENCE COMPLETE` is required before a human reviewer may mark Gate R8 closed. The verifier re-checks the host preflight, candidate SHA linkage, physical/session attestation, required evidence files, and the normal/crash/reboot rollback snapshots rather than trusting the prose summary alone.

## Result semantics

- `PASS`: every mandatory real-host phase passed, exact rollback comparisons passed, cleanup is safe, and the bundle verifier succeeds.
- `FAIL`: product behavior is wrong or unsafe, including partial mutation, false-success UX, failed exact rollback, broken recovery/autostart/state preservation, or privacy leakage.
- `BLOCKED`: a genuine external prerequisite prevents execution, for example the physical Astra stand or approved test upstream proxy is unavailable. A code defect is not `BLOCKED`.

Repository tooling being complete is **not** a real-host PASS. Until the physical Astra Linux Special Edition 1.8 run produces the evidence above, **APL-LNX-010 remains READY/BLOCKED ON REAL HOST and Gate R8 remains PENDING**.
