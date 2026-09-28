# Mac App Store rejection remediation — 2026-09-28

## App Review state

- App: Arvectum Proxy Launcher Mac
- App Store Connect app ID: 6816223569
- Version: 0.2.17
- Rejected build: 1
- Review submission: d07793b2-aaf8-405d-bbca-7d56ba0e3d47
- App Review state: REJECTED / submission UNRESOLVED_ISSUES
- Reported guidelines:
  - 2.1.0 Performance — App Completeness (macOS)
  - 2.4.5 Performance — Hardware Compatibility (macOS)

The public App Store Connect API exposes the state/guideline outcome but not the free-form
Resolution Center message. The detailed reviewer narrative therefore could not be recovered
programmatically from the API.

## Root-cause audit and remediation

### 1. Passive launch mutated Network Extension preferences

Build 1 called VPNController.prepare() on normal app startup. That method called
loadOrCreateManager(), which could create, enable and save a NETunnelProviderManager before
the user pressed Connect.

This behavior was also inconsistent with the App Review notes, which said the macOS system
consent flow would be initiated after the reviewer pressed Connect.

Build 2 changes passive startup to loadExistingManager(). It may read/reload an already
existing Arvectum manager, but it does not create, enable or save a VPN configuration.
loadOrCreateManager() is now reached from the explicit connect() action.

### 2. Mac App Store build exposed non-store release links

The Help screen linked to the GitHub repository and GitHub Releases. Even though the app had
no self-updater, those links could make the Mac App Store build look like it offered an
alternate update/distribution path.

Build 2 removes repository/release links from the Store Help screen. The screen retains the
problem-report/privacy links and explicitly directs updates to Mac App Store -> Updates.

### 3. Current macOS/Xcode compatibility

The Store lane was rebuilt with Xcode 27 / macOS 27 SDK. The app remains intentionally
arm64-only for Apple silicon. The app and embedded Packet Tunnel are sandboxed and
self-contained.

The archive contains no Sparkle updater, installer payload, kext, LaunchAgent, LoginItem,
HelperTool or downloaded executable-code mechanism. It does not use root/setuid behavior.

## Packaging hardening discovered during remediation

The old export helper depended on Xcode automatic/cloud export signing. Under Xcode 27 that
introduced an unnecessary Cloud Managed Certificate permission dependency.

Additionally, multiple historical Mac Installer Distribution identities shared the same
common name. Selecting an installer identity by name could pick a revoked historical
certificate; Apple server validation reproduced this as error 90721.

The Store export helper now verifies the already-signed app archive, loads the dedicated
installer-signing state/keychain, selects the installer certificate by its recorded SHA-1
identity, packages the single app with productbuild, and checks the package signature before
upload.

The installer certificate bootstrap helper now exports a legacy-compatible PKCS#12 so that
macOS security import can consume OpenSSL 3 output correctly.

## Verification evidence

- Contract tests: 14 passed.
- git diff --check: pass.
- Xcode 27 unsigned Release build: BUILD SUCCEEDED.
- Xcode 27 signed App Store Release archive: ARCHIVE SUCCEEDED.
- App bundle: 0.2.17 build 2, arm64.
- Packet Tunnel extension: arm64.
- codesign --verify --deep --strict: pass.
- Release entitlements verified: sandbox + Network Extension + App Group + shared Keychain;
  get-task-allow is false.
- Embedded artifact scan: only Packet Tunnel appex; no updater/installer/kext/login helper.
- Development build on physical Mac mini running macOS 27: BUILD SUCCEEDED.
- Physical passive-launch smoke: app launched and remained running; no app error logs;
  scutil --nc list was unchanged before vs. after passive launch.
- Final package: Arvectum-Proxy-Launcher-macOS-AppStore-0.2.17-build2.pkg.
- Final package SHA-256:
  4fd5b6c1a7aeb5802a95ee59cc3b4f7d0be9eb0ac20ca3db6a956f9bd0246379
- Apple server-side validation: VERIFY SUCCEEDED with no errors.

Xcode 27 emits Swift concurrency warnings in existing shared networking code. They are
warnings under the current Swift 5.9 language mode and did not fail Release, Archive,
Debug, signature validation or Apple server-side package validation.

## Proposed App Review reply

Thank you for the review. We identified and corrected macOS-specific behavior in build 1.

In build 2, launching the app no longer creates, enables, or saves a Network Extension VPN
configuration. The app only reads an existing configuration on passive launch. A VPN
configuration can now be created or enabled only after the user explicitly presses Connect,
at which point macOS may present its system consent UI.

We also removed non-App-Store release/download links from the Mac App Store build. This
build contains no self-updater, and updates are delivered exclusively through the Mac App
Store.

The app and its Packet Tunnel extension are sandboxed and self-contained, use public
NetworkExtension APIs, do not require root/setuid privileges, do not install startup/login
items, kexts, or helper tools, and do not download executable code.

Build 2 was rebuilt and tested with Xcode 27 on macOS 27. The signed package was validated
by Apple's server-side validation successfully with no errors.
