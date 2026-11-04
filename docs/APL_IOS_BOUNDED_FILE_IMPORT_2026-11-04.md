# iOS: bounded proxy file reads before parsing (4 November 2026)

## Defect

The iOS Files importer previously called Data(contentsOf: url) and checked
its 256,000-byte limit only AFTER loading the entire file into memory.
Accidentally selecting a huge TXT/CSV/XML document could create avoidable
memory pressure or terminate the app. This also affects future JSON files,
which are supported by separate PR #335.

## Correction

New SharedCore ProxyImportFileReader opens the locally selected URL with
FileHandle and reads at most 16,384 bytes per request. At the 256,000-byte
boundary it requests one extra byte to detect an oversized file without
buffering the rest. The handle closes with defer on all paths. Non-local
URLs and invalid UTF-8 are rejected; the UI still displays only bounded
ProxyImportUX error messages, not the native filesystem error or path.

The existing iOS file-importer security-scoped URL access, file picker,
parsed-preview behavior, explicit save confirmation, dedup and rollback,
saved profiles, connection state and Keychain are untouched.

## Verified

- Six targeted Swift tests PASS: valid UTF-8/Unicode credentials, empty
  file, exact 256,000-byte limit, 256,001-byte rejection, 4MB file
  rejection, malformed UTF-8 and remote URL refusal.
- Full Swift Core 165/165 PASS.
- Four portable Python bounded-read and privacy contracts PASS;
  full iOS Python suite 137 run (one skipped), no errors.
- XcodeGen and unsigned ARM64 iOS Simulator App+PacketTunnel BUILD PASS.
- Compiled app debug.dylib contains ProxyImportFileReader.readUTF8.
- No real iPhone, user proxy or Apple distribution modified.

An initial independent Python run transiently failed only because it
started while xcodegen was generating a previously missing project file;
after project generation, the full suite was re-run and passed.
No production runtime error was involved.

The new reader is shared by TXT, CSV and XML today, and future JSON import
after the independent PR #335 is merged. Apple release safety checks and
physical Files picker/Keychain acceptance remain separate.
