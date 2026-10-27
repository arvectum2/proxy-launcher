# Arvectum Proxy Launcher iOS — published 0.1.37 (41), metadata audit, and next-version corrections

Audit date: 2026-10-27
Source of truth: Apple iTunes Lookup API and authenticated App Store Connect API.
Public store: https://apps.apple.com/ru/app/arvectum-proxy-launcher/id6816013574
Bundle: `ru.arvectum.proxylauncher.ios`

## Verified current state

- Published App Store version: **0.1.37**, build **41**. Apple App Store Connect state: `READY_FOR_SALE`. Public Apple Lookup `currentVersionReleaseDate`: `2026-10-07T15:55:15Z`.
- Live localization `ru`: Support URL = `https://arvectum2.github.io/proxy-launcher/support.html`; Marketing URL = `https://github.com/arvectum2/proxy-launcher`.
- Live localization `en-US`: same Support URL and Marketing URL.
- Public iTunes Lookup API `sellerUrl` resolves to GitHub; this is the website discovered by RСЯ when checking the developer's website.
- Verified external website: `https://arvectum.com/` HTTP 200 with contact link; `https://arvectum.com/app-ads.txt` HTTP 200, 7896 bytes on 2026-10-27. The ordinary `/ads.txt` file is **not** the required mobile-app inventory file.
- **Apple API state limitation:** PATCH `/v1/appStoreVersionLocalizations/{id}` attempting to set `supportUrl` and `marketingUrl` for live 0.1.37 returned HTTP 409 `STATE_ERROR`, with details `Attribute 'marketingUrl' cannot be edited at this time` and `Attribute 'supportUrl' cannot be edited at this time`. No change was applied to the live release.

## Correct values for the next App Store version (all supported localizations)

| Field | Target |
| --- | --- |
| `supportUrl` | `https://arvectum.com/` |
| `marketingUrl` | `https://arvectum.com/` |

The marketing/developer website URL is critical for RСЯ `app-ads.txt` verification. The Support URL change alone is insufficient. Keep the privacy policy URL unchanged until its target and disclosure content have been reviewed; it is a separate App Store Connect property.

## Release gate and verification

1. Open a **new** iOS App Store version after explicit owner authorization; do not modify or replace the already published version 0.1.37.
2. In each locale of the new version, change Support URL and Marketing URL to `https://arvectum.com/`.
3. Prepare an updated version/build with unchanged VPN functionality, run relevant tests, upload for App Review and obtain owner release approval.
4. After approval and public availability, confirm Apple Lookup `sellerUrl` now points to `https://arvectum.com/`, App Store product-page Developer Website points to same domain, and user-facing Support URL is corrected.
5. Then request re-verification in Yandex RСЯ. Their `app-ads.txt` documentation indicates a daily verification cadence; allow up to 24 hours for the status to update.

This document is a verified metadata snapshot and implementation plan, **not** a claim of successfully editing the live 0.1.37 listing. Earlier 0.1.36 (40) metadata/evidence documents remain historical and immutable.

References:
- https://developer.apple.com/documentation/appstoreconnectapi/app-store-version-localizations
- https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/
- https://ads.yandex.com/helpcenter/ru/monetization/app/ads-txt
