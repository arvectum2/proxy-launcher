# APL-ANDROID-BATCH-IMPORT-20261126
## Scope
Explicit multiline text and UTF-8 TXT file import of existing ordinary proxy formats. No QR, CSV, JSON, native transports, subscription fetching, VPN or release changes.
## Requirements
- B1: at most 256000 UTF-8 bytes, 200 non-comment entries, strict decoding, bounded stream reads, no partial parse of malformed input.
- B2: duplicate key = transport, case-insensitive host, port, username. Existing and earlier entries win; no password comparison or overwrite. Preview count and endpoint-only summary; no secrets in error/status/logs.
- B3: disconnected-only; manual paste or system document picker, no persisted URI permission or automatic reading of clipboard. Explicit preview and explicit Save; cancel does not persist.
- B4: recheck duplicate set and disconnected state before save. Stage encrypted credentials and profile metadata in one SharedPreferences editor commit, preserve selection and priority, no auto VPN. Do not claim database ACID semantics.
- B5: JVM/contract tests and exact Android CI. Device smoke separately. No new release/signature.
