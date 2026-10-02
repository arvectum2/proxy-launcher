# Mac App Store review remediation — 2026-10-02

## Review result

macOS 0.2.17 build 3 was rejected again on 2026-10-01 with three reviewer requests:

1. Guideline 5.2.5: remove inappropriate use of the Apple product term “Mac” from the App Store product name.
2. Guideline 2.1(a): provide reviewer-accessible credentials or another way to exercise the full connection flow.
3. Guideline 2.1: explain what information is handled through the VPN/Network Extension path, why it is handled, whether it is shared, and where it is stored.

## Remediation

No binary rebuild was required.

- App Store product name changed from `Arvectum Proxy Launcher Mac` to `Proxy Launcher by Arvectum`.
- The installed bundle name remains `Arvectum Proxy Launcher`; source metadata already used that non-Apple product name.
- App Review Information explicitly states that APL has no user account or sign-in.
- A temporary private review-only HTTP/HTTPS CONNECT proxy and exact test steps were added to App Review Information. Credentials remain only in App Store Connect and are not committed to the repository.
- The review proxy was tested immediately before resubmission and returned HTTP 200 through the authenticated proxy path.
- App Review Information now gives direct answers to Apple’s VPN/data questions: Arvectum does not collect or receive traffic/user information; packet data is processed transiently on-device solely for forwarding; profile/routing state remains local; passwords use Apple Keychain; the local journal stores connection status/profile/error data only; there is no Arvectum cloud backend, analytics, advertising, or tracking in this build; user traffic goes only to the user-selected proxy and destination.
- A direct reply with the same clarification was sent in the App Review conversation.

## Resubmission evidence

- App Store Connect app ID: `6816223569`
- Review submission: `d07793b2-aaf8-405d-bbca-7d56ba0e3d47`
- App Store version/build: `0.2.17 (3)`
- Build state: `VALID` / `APP_STORE_ELIGIBLE`
- Minimum macOS: `13.0`
- Export compliance: `usesNonExemptEncryption=false`
- Review item: `REJECTED -> READY_FOR_REVIEW`
- Resubmission PATCH: HTTP 200
- Final submission state: `WAITING_FOR_REVIEW`
- Final app version state: `WAITING_FOR_REVIEW`
- Resubmitted at: `2026-10-02T06:50:28.736Z`

Do not rebuild or re-upload build 3 unless Apple reports a new concrete binary issue.
