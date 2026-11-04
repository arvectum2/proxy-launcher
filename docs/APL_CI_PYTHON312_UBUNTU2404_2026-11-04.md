# CI repair — Python 3.12.10 on Ubuntu 24.04 (4 November 2026)

## Observed breakage on iOS PR #316

Six otherwise independent GitHub Actions jobs all failed at setup-python before running a single test, while iOS-native local tests and iPhone Simulator UI were green.

Exact hosted failure from SBOM/SAST/APL-IP and sovereignty jobs:
"The version '3.12.10' with architecture 'x64' was not found for Ubuntu 26.04."

Root cause: these six Python security/contract workflows used ubuntu-latest, which scheduled on Ubuntu 26.04 without matching action-managed Python 3.12.10. The error does not mean the iOS code or security checks actually ran.

## Minimal, reproducible fix

Pin precisely the following workflows to runs-on: ubuntu-24.04 without changing job steps, permissions, pinned setup-python action SHA, exact BUILD_PYTHON_VERSION 3.12.10, dependencies, security gates or failure conditions:

- dependency-scan.yml — pip-audit
- sast.yml — Bandit SAST
- sbom.yml — CycloneDX SBOM
- apl-ip-001-v0-2-5.yml — clean-IP reconciliation
- apl-ip-001-v0-2-9.yml — clean-IP reconciliation
- apl-reg-001b-sovereign-lifecycle.yml — sovereign lifecycle contract

Other workflows, including Windows and macOS builds, were left unchanged. This is intentionally a separate infrastructure PR from iOS UI PR #316.

## Validation

- 16/16 locally targeted Python source/engineering/release-contract tests PASS.
- Ruby YAML parse succeeds for all six modified workflow files.
- git diff --check PASS. The only workflow differences are six runner selectors.
- Hosted CI at the exact repaired commit remains an acceptance gate. Once merged, refresh PR #316 against the new main and re-run checks rather than overriding failed security gates.

No Apple App Store submission, production device/VPN, user proxy, Mac mini system service or disabled Proxy Launcher Watchdog was changed.
