# macOS App Store candidate 0.2.19 (5) — UI recovery (not submitted)

**Release gate: obtain explicit owner approval before submitting for Apple App Review or public release.** This is a private build candidate only.

## User-facing improvements
- Primary Connect/Disconnect action is now an accessible, full-width 80 pt button instead of the 116 pt round macOS button.
- Live status is easier to read, with a pill and a separate state indicator; action remains disabled while the native VPN is disconnecting.
- First-time setup no longer leads to an empty selection menu: it clearly offers "Добавить прокси" directly in both connection and profile cards.
- Adjusted copy to describe selected *mode* rather than claiming "Авто" is a particular active proxy.
- Troubleshooting guide explains that a Telegram-specific localhost SOCKS setting used by the retired developer build can prevent Telegram from connecting despite a functioning device-wide Packet Tunnel.

## Verified functionality inherited from 0.2.18
- Split DNS excludes exact configured site hostnames from VPN while other sites remain proxied.
- The user confirmed Telegram for macOS works through native APL once the old Telegram app-specific proxy is switched off.
- Existing system-wide manual HTTP/HTTPS/SOCKS/PAC proxy settings remain off.

## No advertising in this candidate
Ads/sponsorship have been postponed by the owner. No sponsor placement view, inventory, SDK, advertising integration, tracking, ad disclosure changes or paid functionality is present. The previous concept is retained only as backlog documentation (outside this branch).

## Validation before submitting
- Build signed Mac Catalyst archive and locally verify user interface on MacBook or internal TestFlight when owner agrees.
- Run macOS App Store contract tests and all GitHub checks.
- Confirm existing Network Extension VPN continues to work and Telegram stays connected.
- Owner specifically confirms "submit 0.2.19 (5) to Apple App Review" after reviewing the final candidate.
