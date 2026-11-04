# iOS: offline JSON proxy provider import (4 November 2026)

## What changed

The preexisting proxy URL, QR, host:port:user:password, TXT, CSV and XML
importer now additionally accepts offline JSON from iOS Files and pasted text.

Supported provider shapes:
- A single record with host and port, optional username, password, type/name.
- An array of such objects or proxy URL strings (mixed arrays supported).
- A wrapper object with one proxies array.
- The same field aliases as CSV/XML (host/ip/server/address, username/login,
  password/pass, protocol/type, label/name); optional default type applies
  only when a type is omitted.

## Privacy and safety

- Strict 256,000-byte input and 200-proxy limits across formats.
- Every JSON record must parse successfully; no partial import on error.
- Invalid or ambiguous field aliases, unknown nested objects, boolean or
  fractional ports, unsupported protocols, missing ports and malformed
  credentials are rejected without exposing secrets.
- Existing preview, dedup, user confirmation, rollback and one bounded
  after-import connection scan are unchanged.
- Raw bracketed IPv6 host:port credentials are not mistaken for JSON arrays.
- No network fetch, arbitrary code, Keychain mutation on parsing or VPN
  start action.
- JSON UTType added to the Files importer.
- Existing key for the format-help localization remains byte-for-byte
  unchanged; only translated values extend TXT/CSV/XML to TXT/CSV/XML/JSON
  across all 64 languages.

## Local verification

- 6/6 focused Swift JSON tests, full Swift Core 165/165 PASS.
- 5/5 Python source and 64-locale contracts; full iOS Python 133 tests,
  one skipped, no failures.
- plutil -lint validates all 64 iOS ProxyImport.strings files.
- XcodeGen, unsigned ARM64 Simulator App+PacketTunnel build PASS.
- Real compiled app debug.dylib includes ProxyImportStructured.json symbol.

No physical iPhone or signed Apple IPA was tested here. Apple App Review
and two-iPhone QR acceptance are separate release gates. Native draft
PR #314 is excluded.
