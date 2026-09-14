# APL-REG-001C — RED OS real-host acceptance

Status: **TOOLING PREPARED; PHYSICAL RED OS RUN REQUIRED**.

This is the second trusted-OS record for APL-REG-001C. The first record, Astra Linux SE / APL-LNX-010, is already complete. Generic Fedora/Ubuntu CI, a container or a successful RPM build does not satisfy this gate.

## Canonical target

- RED OS 8 workstation, x86_64;
- normal interactive graphical session;
- NetworkManager managing the tested primary connection;
- exact governed `arvectum-proxy-launcher-*.x86_64.rpm` candidate;
- preferably the physical acceptance laptop used for the Astra run, after RED OS is installed alongside the existing systems.

Before the run, re-check that the exact RED OS edition/version remains acceptable for the registry evidence purpose and that the different-rightsholder condition still holds. Legal/classifier conclusions are not inferred by this technical tooling.

## Safety invariants

1. Capture NetworkManager proxy state before the first product mutation.
2. Never delete pending rollback state to make a test pass.
3. Never replace product-owned rollback with a blanket NetworkManager reset.
4. If a foreign/newer change blocks safe rollback, stop and retain evidence; do not overwrite it.
5. Run the product from the normal logged-in graphical user, not as a permanently privileged process.
6. Keep raw screenshots/logs/support bundles private when they expose local paths, usernames or network details.
7. `RESULT: PASS` is forbidden until final NetworkManager proxy state mechanically equals the baseline and no rollback remains pending.

## Tooling

- `qa/collect_redos_acceptance_preflight.sh` / `.py` — strict read-only RED OS + RPM preflight;
- `qa/collect_redos_network_state.py` — privacy-preserving NetworkManager proxy snapshot;
- `qa/compare_redos_network_state.py` — exact rollback comparator;
- `qa/verify_redos_acceptance_bundle.py` — fail-closed final verifier.

The snapshot stores SHA-256 identities instead of raw connection UUIDs, PAC URLs or PAC scripts.

## Evidence directory

```bash
EVIDENCE="$HOME/APL-REG-001C-REDOS-$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 "$EVIDENCE"
export EVIDENCE
```

Required files:

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

## Phase 0 — freeze source and RPM

From a clean checkout of the exact candidate source:

```bash
{
  git status --short
  git rev-parse HEAD
  git log -1 --oneline
  python3 --version
} > "$EVIDENCE/00-repository.txt"

python3 -m unittest \
  tests.test_redos_real_host_acceptance_tooling \
  tests.test_linux_backend \
  tests.test_linux_networkmanager_preflight \
  tests.test_linux_policykit_ux \
  tests.test_linux_runtime \
  tests.test_linux_runtime_preflight_wiring \
  tests.test_linux_autostart \
  tests.test_linux_diagnostics

CANDIDATE=/absolute/path/to/arvectum-proxy-launcher-VERSION-1.red*.x86_64.rpm
```

No deterministic failure may be waived.

## Phase 1 — strict read-only preflight and baseline

```bash
bash qa/collect_redos_acceptance_preflight.sh \
  "$EVIDENCE/01-preflight.txt" "$CANDIDATE"

python3 qa/collect_redos_network_state.py \
  "$EVIDENCE/02-network-before.json"
```

PASS requires strict RED OS detection, x86_64, non-CI/non-virtual physical acceptance, graphical session availability, `dnf`/`rpm`/`nmcli`, at least one relevant active NetworkManager connection, and candidate package identity/SHA-256.

After physically confirming the host/session:

```bash
cat > "$EVIDENCE/HOST_ATTESTATION.env" <<'ATTEST'
physical_host=YES
interactive_graphical_session=YES
operator_confirmed=YES
ATTEST
chmod 600 "$EVIDENCE/HOST_ATTESTATION.env"
```

## Phase 2 — RPM install and GUI

Record commands/results and the candidate SHA in `03-package.txt`:

```bash
sha256sum "$CANDIDATE"
rpm -qpi "$CANDIDATE"
rpm -qp --requires "$CANDIDATE"
sudo -E dnf install "$CANDIDATE"
rpm -q arvectum-proxy-launcher
```

Launch `arvectum-proxy-launcher` from the graphical user session and record `04-gui.md`. PASS requires a normal GUI start and truthful Linux backend/capability reporting.

## Phase 3 — real proxy enable and no-proxy routing

Exercise the normal NetworkManager preflight and PolicyKit flow. Use an approved acceptance proxy without writing its credentials into evidence. Record observations in `05-enable.md`, including one positive proxied route and one explicit no-proxy/bypass case.

After enable:

```bash
python3 qa/collect_redos_network_state.py \
  "$EVIDENCE/06-network-enabled.json"
```

PASS requires real product-owned proxy state on supported active profiles, a successful intended proxied route, a successful no-proxy route, and durable rollback evidence created before mutation.

## Phase 4 — normal disable and exact rollback

```bash
python3 qa/collect_redos_network_state.py \
  "$EVIDENCE/08-network-after-disable.json"
python3 qa/compare_redos_network_state.py \
  "$EVIDENCE/02-network-before.json" \
  "$EVIDENCE/08-network-after-disable.json" \
  | tee "$EVIDENCE/07-disable.md"
```

Comparator exit code 0 is mandatory.

## Phase 5 — autostart/login

Enable the product's normal per-user autostart, log out/in, and verify one normal graphical launch. Disable autostart again unless the stand owner wants it retained. Record `09-autostart.md`. Autostart itself must not mutate proxy state.

## Phase 6 — crash/relaunch recovery

From baseline, enable proxy state, terminate the app without normal disable, relaunch, recover/disable, then capture and compare:

```bash
python3 qa/collect_redos_network_state.py "$EVIDENCE/11-network-after-crash-recovery.json"
python3 qa/compare_redos_network_state.py "$EVIDENCE/02-network-before.json" "$EVIDENCE/11-network-after-crash-recovery.json"
```

Record `10-crash-recovery.md`. Pending rollback must survive the crash and clear only after successful restoration.

## Phase 7 — reboot/login recovery

With autostart enabled and product-owned proxy state active, reboot normally. After graphical login, prove pending recovery remains detectable, recover/disable, then capture/compare:

```bash
python3 qa/collect_redos_network_state.py "$EVIDENCE/13-network-after-reboot-recovery.json"
python3 qa/compare_redos_network_state.py "$EVIDENCE/02-network-before.json" "$EVIDENCE/13-network-after-reboot-recovery.json"
```

Record `12-reboot-recovery.md`.

## Phase 8 — update/remove and state preservation

Only from clean proxy state:

```bash
sudo -E dnf reinstall "$CANDIDATE"
rpm -q arvectum-proxy-launcher
sudo -E dnf remove arvectum-proxy-launcher
```

Record `14-update-remove.md`. Package lifecycle must not fabricate rollback, unexpectedly erase user-owned state, or leave proxy mutation behind. Reinstall if needed for final diagnostics.

## Phase 9 — diagnostics/privacy and cleanup

Generate the implemented Linux diagnostics/support output and manually inspect it. Record `15-diagnostics-privacy.md`. It must not expose proxy passwords/tokens, raw rollback payload, environment dumps, browser history or unrelated home-directory content.

Before PASS, restore intended no-proxy/autostart settings, disable product proxy, prove the final snapshot equals `02-network-before.json`, confirm no pending `linux_proxy_backup.json`, and verify normal connectivity.

## SUMMARY.md contract

```text
APL-REG-001C — REAL RED OS ACCEPTANCE
RESULT: PASS

ACCEPTANCE:
- read-only preflight: PASS
- RPM install/remove/update: PASS
- GUI launch/platform UX: PASS
- NetworkManager runtime/preflight: PASS
- PolicyKit authorization UX: PASS
- real enable: PASS
- no-proxy routing: PASS
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

Finally:

```bash
python3 qa/verify_redos_acceptance_bundle.py "$EVIDENCE"
```

`APL-REG-001C RED OS VERDICT: EVIDENCE COMPLETE` is required before the second trusted-OS record can be marked complete. Repository tooling or an RPM CI artifact alone is never a real-host PASS.
