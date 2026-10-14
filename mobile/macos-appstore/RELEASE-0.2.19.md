# macOS App Store candidate 0.2.19 (7) — UI recovery (not submitted)

**Release gate: obtain explicit owner approval before submitting for Apple App Review or public release.** This is a private build candidate only.

## User-facing improvements
- Primary Connect/Disconnect action is now an accessible, full-width 80 pt button instead of the 116 pt round macOS button.
- Live status is easier to read, with a pill and a separate state indicator; action remains disabled while the native VPN is disconnecting.
- First-time setup no longer leads to an empty selection menu: it clearly offers "Добавить прокси" directly in both connection and profile cards.
- Adjusted copy to describe selected *mode* rather than claiming "Авто" is a particular active proxy.
- macOS Settings no longer displays a dead-end app-exclusions button; that automation remains available only in iOS, where the implementation exists.
- Desktop dashboard cards have identical height in two-column mode; when the window narrows below the two-column breakpoint, the Profile card moves below Connection automatically, without a fixed height that would clip text.
- Desktop sidebar wordmark and title stack vertically instead of truncating "Proxy Launcher"; menu labels stay on one line.
- Reduced the macOS minimum window height so the dashboard can be compacted instead of forcing unused empty space; the scroll view retains access to both cards in stacked mode.
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

## Critical site-exclusion fix in build 7
- Normal website address and its www alias are paired for native real-DNS answers and excluded physical IP routes (e.g. gosuslugi.ru + www.gosuslugi.ru, www.zakupki.gov.ru + zakupki.gov.ru).
- Nonexistent aliases are optional and skipped, so profiles excluding a concrete host or raw IP still connect.
- Other subdomains are still exact and must be configured explicitly; this does not claim recursive wildcard/DNS TTL support.
- DO NOT submit App Review or release pending real MacBook TestFlight HTTPS verification and fresh owner authorization.
