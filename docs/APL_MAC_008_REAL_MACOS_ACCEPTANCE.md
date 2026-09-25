# APL-MAC-008 — Real macOS acceptance

Status: **DONE — REAL HOST PASS**

Gate: **R9 CLOSED from the real-host acceptance recorded below.**

Gate R9 required all mandatory real-host checks to pass on a real Mac in a normal interactive Aqua session; hosted CI, mocks and packaging inspection alone were not sufficient.

## Real-host acceptance result

Date: 2026-08-17

Result: PASS

Candidate:
0e83da8f270d3d9fe95e2743e641ff150b7014d2

Product:
0.2.3

Host:
- MacBook Pro (M2)
- macOS 26.6.1 (25G76)
- arm64
- interactive Aqua session

Package:
- Arvectum_Proxy_Launcher-0.2.3-arm64.dmg
- SHA256:
  f006b1cb30358e2ae6b8e3fabdc514878e201efd5a33071bfcbd16dcb8e4f86b
- hdiutil verify: PASS
- bundle id: ru.arvectum.proxylauncher

Network acceptance:
- baseline SHA256:
  8edbdaa388801b82ab156243f5eb770442b4b1e855138fbbcb4f9993851e5549
- real enable: PASS
- bypass sync: PASS
- normal disable exact rollback: PASS
- crash/relaunch recovery: PASS
- real reboot/login recovery: PASS
- final comparator: PASS
- pending rollback after cleanup: NO

Authorization:
- normal interactive user: YES
- whole app as root: NO
- sudo networksetup: NO
- system authorization prompt observed: NO
- direct networksetup mutation succeeded under tested host/user policy

Autostart:
- canonical LaunchAgent: PASS
- real login launch: PASS
- legacy LaunchAgent: absent

Mutable state:
- canonical Application Support root: PASS
- state outside .app: PASS
- update/replacement preservation: PASS

Diagnostics:
- privacy review: PASS
- credentials absent
- environment dump absent
- browser/home-directory data absent
- rollback contents absent

Final safety state:
- proxy OFF
- network restored to proven baseline
- pending rollback: NO
- test-only bypass: NO

Gate:
- APL-MAC-008: DONE
- Gate R9: DONE

Raw machine/network evidence remains private and is intentionally not committed.

## Purpose

Close the remaining macOS functional acceptance boundary for the current system-proxy product line:

- real `.app` / DMG launch and GUI behavior;
- real `networksetup` capability and mutation behavior;
- enable / bypass sync / disable with proven rollback;
- per-user LaunchAgent ownership and login behavior;
- crash / relaunch / reboot recovery;
- update/remove behavior without loss of user state or rollback ownership;
- one real diagnostics/support bundle privacy review.

Production Apple identity signing/notarization was intentionally outside the historical APL-MAC-008 functional gate. It is now handled by a separate release-trust lane: Developer ID + Apple notarization may change distribution trust, but does not rewrite the already-closed functional acceptance record.

## Safety invariants

1. Never run a generic macOS proxy reset as a shortcut.
2. Never delete `~/Library/Application Support/Arvectum/ProxyLauncher/macos_proxy_backup.json` while rollback is pending.
3. Capture an exact read-only baseline before the first proxy mutation.
4. Restore through the product-owned `disable` / rollback path whenever ownership is valid.
5. If the product refuses rollback because the live state no longer matches Arvectum-owned state, **stop**. Do not overwrite the foreign/newer state. Capture evidence and mark the case FAIL/BLOCKED until a deliberate operator recovery is performed from the pre-captured baseline.
6. Do not commit raw acceptance evidence that may contain PAC URLs, service names, proxy configuration, usernames or other local-machine data.
7. Acceptance must be performed from the normal logged-in user session, not only via SSH/headless execution.
8. The legacy root `install.command` / `uninstall.command` path is not the canonical APL-MAC-008 packaging path. Test the APL-MAC-004/005 `.app` + DMG path in `/Applications`.

## Canonical paths

- app: `/Applications/Arvectum Proxy Launcher.app`
- bundle id: `ru.arvectum.proxylauncher`
- LaunchAgent: `~/Library/LaunchAgents/ru.arvectum.proxylauncher.plist`
- rollback evidence: `~/Library/Application Support/Arvectum/ProxyLauncher/macos_proxy_backup.json`
- read-only preflight: `qa/collect_macos_acceptance_preflight.sh`
- exact state collector: `qa/collect_macos_network_state.py`
- rollback comparator: `qa/compare_macos_network_state.py`

## Known pre-acceptance integration check

At the repository baseline used to author this runbook, `macos_autostart.py` implements the APL-MAC-006 LaunchAgent contract, but the shared `proxy_gui.py` still contains Windows-specific autostart UI/handlers and Windows-specific recovery wording.

Before the real acceptance run, inspect the exact candidate commit. If this is still true, treat it as a **repository-side blocker**, not as a manual-test exception. Fix it first, add deterministic tests, and rerun the automated suite. The macOS GUI must:

- present platform-correct autostart wording;
- use `macos_autostart.is_autostart_enabled`, `enable_autostart`, and `disable_autostart` on Darwin;
- never invoke Windows Registry / Task Scheduler autostart paths on Darwin;
- keep the canonical `ru.arvectum.proxylauncher` LaunchAgent path and `/Applications/...app` executable target;
- use platform-neutral/macOS recovery wording rather than claiming Windows state is being restored;
- preserve the proven Windows 0.2.3 behavior and tests unchanged.

Do not close APL-MAC-008 with a known Windows-only GUI control merely because the standalone macOS module passes unit tests.

## Evidence directory

Create a private local directory outside tracked source files, for example:

```bash
EVIDENCE="$HOME/Desktop/APL-MAC-008-$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 "$EVIDENCE"
```

Recommended contents:

- `00-repository.txt`
- `01-preflight.txt`
- `02-network-before.json`
- `03-package.txt`
- `04-gui.md`
- `05-enable.txt`
- `06-network-enabled.json`
- `07-sync.txt`
- `08-network-after-disable.json`
- `09-autostart.txt`
- `10-crash-recovery.txt`
- `11-network-after-crash-recovery.json`
- `12-reboot-recovery.txt`
- `13-network-after-reboot-recovery.json`
- `14-update-remove.txt`
- `15-diagnostics-privacy.txt`
- `support-bundle.zip` (local/private only)
- `SUMMARY.md`

Screenshots are useful for GUI evidence but must not expose proxy passwords/tokens.

## Phase 0 — repository and automated gate

Record exact source identity:

```bash
git status --short
git rev-parse HEAD
git log -1 --oneline
python3 --version
```

Requirements:

- working tree clean before acceptance changes;
- exact candidate commit recorded;
- run at minimum all `tests/test_macos*.py`, `tests/test_backend_contract_matrix.py`, `tests/test_backend_runtime*.py`, and `tests/test_proxy_gui.py`;
- after any pre-acceptance remediation, run the full test suite before building the candidate;
- no failing test may be waived to obtain a real-host PASS.

## Phase 1 — read-only preflight and baseline

Run before any network mutation:

```bash
bash qa/collect_macos_acceptance_preflight.sh "$EVIDENCE/01-preflight.txt" "${DMG:-}"
python3 qa/collect_macos_network_state.py "$EVIDENCE/02-network-before.json"
```

PASS requires:

- Darwin/macOS runtime and architecture recorded;
- `/usr/sbin/networksetup` available;
- at least one enabled network service;
- PAC/bypass state readable for enabled services;
- no unexplained pre-existing Arvectum rollback evidence.

If rollback evidence already exists, do not overwrite/delete it. Treat this as a recovery case first and document the result before starting a clean baseline.

## Phase 2 — build/package/install/GUI

Use the canonical APL-MAC-004/005 path. Prefer an exact release-candidate DMG tied to the recorded commit; otherwise build from that exact clean commit:

```bash
bash tools/build_macos_app.sh
bash tools/build_macos_dmg.sh
```

Record `shasum -a 256` and `hdiutil verify` for the exact DMG.

Install via the DMG/Finder model into `/Applications`. Verify:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  '/Applications/Arvectum Proxy Launcher.app/Contents/Info.plist'
open -a 'Arvectum Proxy Launcher'
```

PASS requires:

- bundle id exactly `ru.arvectum.proxylauncher`;
- application launches in the interactive session and presents a usable GUI;
- no immediate crash;
- controls/text are platform-correct;
- capability/preflight failure is reported truthfully; unavailable/auth-required is not shown as successful enablement.

## Phase 3 — real enable and owned-state observation

Use a real testable upstream proxy configuration already approved for this acceptance run. Do not write credentials into evidence files.

Immediately before clicking **Enable**, ensure the Phase 1 baseline exists. Enable through the normal product UI.

Observe independently with read-only commands and collect:

```bash
python3 qa/collect_macos_network_state.py "$EVIDENCE/06-network-enabled.json"
stat -f '%Sp %N' "$HOME/Library/Application Support/Arvectum/ProxyLauncher/macos_proxy_backup.json"
```

PASS requires:

- product proxy process starts;
- rollback evidence exists and is mode 0600 after enable;
- the product-owned PAC is enabled on the network services snapshotted by the backend;
- configured no-proxy domains are merged with, not substituted for, the original bypass state;
- connection test succeeds through the intended route when the upstream proxy itself is available;
- failure to mutate does not claim success and does not leave partial unowned state.

## Phase 4 — bypass sync

Exercise one real no-proxy edit through the product UI. Prefer a harmless acceptance-only domain such as `apl-mac-008.invalid`, and record the user's original no-proxy configuration before editing it.

PASS requires:

- sync changes only the owned bypass dimension;
- PAC identity remains the same;
- original pre-enable snapshot remains recoverable;
- restore the user's original no-proxy configuration before the end of the test.

## Phase 5 — normal disable and exact rollback

Disable/restore through the normal product UI. Then capture:

```bash
python3 qa/collect_macos_network_state.py "$EVIDENCE/08-network-after-disable.json"
python3 qa/compare_macos_network_state.py \
  "$EVIDENCE/02-network-before.json" \
  "$EVIDENCE/08-network-after-disable.json"
```

PASS requires comparator exit code 0 and:

- original automatic-proxy enabled flag restored for every baseline service;
- original PAC URL restored;
- original bypass-domain set restored;
- rollback evidence removed only after successful restoration;
- product process stopped as expected.

## Phase 6 — LaunchAgent/autostart

From the macOS GUI, enable autostart. Verify:

```bash
PLIST="$HOME/Library/LaunchAgents/ru.arvectum.proxylauncher.plist"
plutil -lint "$PLIST"
stat -f '%Sp %N' "$PLIST"
/usr/libexec/PlistBuddy -c 'Print :Label' "$PLIST"
/usr/libexec/PlistBuddy -c 'Print :RunAtLoad' "$PLIST"
/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST"
```

PASS requires:

- label `ru.arvectum.proxylauncher`;
- `RunAtLoad=true`;
- executable points to the canonical `/Applications/Arvectum Proxy Launcher.app` binary;
- file is user-owned and mode 0600;
- no root LaunchDaemon/system-wide startup item is created;
- logout/login (or the reboot phase below) launches the app once in an Aqua session;
- disabling autostart removes only the owned plist and does not mutate proxy state.

## Phase 7 — crash/relaunch recovery

Start again from the recorded clean baseline. Enable proxy normally and prove rollback evidence exists. Then forcibly terminate the product process without using its normal stop path.

Relaunch the GUI manually.

PASS requires:

- pending recovery is detected from durable evidence;
- GUI does not silently describe the network as clean;
- recovery/disable remains reachable even if enable preflight later degrades;
- invoking recovery restores the baseline;
- collect `11-network-after-crash-recovery.json` and compare it to `02-network-before.json` with the comparator;
- rollback evidence is removed only after successful recovery.

## Phase 8 — reboot recovery + real login-session autostart

Enable autostart. From a clean baseline, enable proxy and confirm rollback evidence exists. Reboot macOS normally while the owned proxy state is active.

After login:

- verify the LaunchAgent caused the canonical app to launch in the Aqua session;
- verify pending rollback/recovery state is still detectable;
- perform recovery/disable through the product;
- capture `13-network-after-reboot-recovery.json`;
- compare to `02-network-before.json`.

PASS requires exact comparator PASS and no orphan rollback evidence after successful recovery.

## Phase 9 — update/remove behavior

Test replacement of the installed `.app` with the same/newer candidate while proxy is **disabled and clean**. User settings/no-proxy configuration must remain intact.

Then test removal of the `.app` only after confirming:

- proxy process is stopped;
- no rollback is pending;
- network snapshot equals baseline.

The DMG path has no installer/uninstaller network hooks. Removing the `.app` must not be used as a substitute for rollback. If proxy is active/pending, removal is a FAIL condition until recovery is completed.

Legacy `install.command`/`uninstall.command` behavior is not evidence for this gate and must not create a second autostart/network-state owner during the test.

## Phase 10 — real diagnostics privacy review

Generate one support bundle directly from the implemented macOS diagnostics contract, for example:

```bash
python3 - <<'PY'
from macos_diagnostics import write_macos_support_bundle
import os
out = os.environ['EVIDENCE'] + '/support-bundle.zip'
print(write_macos_support_bundle(out))
PY
unzip -l "$EVIDENCE/support-bundle.zip"
unzip -p "$EVIDENCE/support-bundle.zip" diagnostics.json > "$EVIDENCE/diagnostics.json"
```

Manually inspect `diagnostics.json` before sharing it.

PASS requires:

- bounded OS/runtime/preflight/service metadata only;
- no proxy password/token/credential;
- no environment dump;
- no browser history;
- no home-directory listing;
- no rollback JSON payload contents;
- no secret accidentally copied from the user's settings.

## Final cleanup

Before declaring PASS:

- restore the user's original no-proxy configuration;
- restore the intended original autostart choice;
- stop the proxy unless the operator explicitly wants it enabled after acceptance;
- prove final network state equals `02-network-before.json` if the intended final state is baseline;
- prove no unwanted `macos_proxy_backup.json` remains;
- prove no legacy `com.arvectum.proxylauncher.plist` was introduced by the canonical acceptance path.

## Final result contract

`RESULT: PASS` is allowed only when all required phases pass and every mutation path finishes in a proven safe state.

`RESULT: FAIL` if a product behavior is wrong, including GUI/platform wiring, partial proxy mutation, failed rollback, privacy leakage, wrong LaunchAgent ownership, or bad crash/reboot recovery.

`RESULT: BLOCKED` only for a genuine external prerequisite (for example, no usable approved upstream proxy or inability to perform the required interactive reboot/login), not for a code defect.

The final `SUMMARY.md` must contain:

```text
APL-MAC-008 — REAL macOS ACCEPTANCE
RESULT: PASS | FAIL | BLOCKED

SOURCE:
- repository: arvectum/proxy-launcher
- branch/ref:
- commit SHA:
- product version:

HOST:
- macOS version:
- architecture:
- interactive Aqua session: YES/NO

PACKAGE:
- DMG path/name:
- DMG SHA256:
- hdiutil verify: PASS/FAIL
- bundle id: ru.arvectum.proxylauncher PASS/FAIL

ACCEPTANCE:
- read-only preflight: PASS/FAIL
- GUI launch/platform UX: PASS/FAIL
- real enable: PASS/FAIL
- bypass sync: PASS/FAIL
- normal disable exact rollback: PASS/FAIL
- LaunchAgent/autostart: PASS/FAIL
- crash/relaunch recovery: PASS/FAIL
- reboot/login recovery: PASS/FAIL
- update/remove + user-state preservation: PASS/FAIL
- diagnostics privacy: PASS/FAIL
- final cleanup / no pending rollback: PASS/FAIL

NETWORK EVIDENCE:
- baseline snapshot SHA256:
- post-disable snapshot SHA256:
- post-crash-recovery snapshot SHA256:
- post-reboot-recovery snapshot SHA256:
- comparator results: PASS/FAIL

REPOSITORY CHANGES MADE DURING ACCEPTANCE:
- none | commit(s)/PR(s):

DEFECTS / DEVIATIONS:
- ...

GATE R9:
- CLOSED only if RESULT=PASS
```

## Gate closure

Only after `RESULT: PASS`:

1. update this document status to **DONE — REAL HOST PASS** and record non-secret evidence identifiers/hashes;
2. update `docs/ROADMAP.md`: APL-MAC-008 = **DONE** and Gate R9 = **DONE**;
3. update `docs/LOCAL_EXECUTION_BACKLOG.md` to remove/close P4;
4. commit the non-secret acceptance summary (not raw machine-sensitive evidence) and merge through the canonical repository workflow.

If any phase fails, leave Gate R9 open, fix the defect, rebuild from a clean candidate commit, and rerun the affected real-host phases plus final rollback verification.
