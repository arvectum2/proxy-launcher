# Tasks
- [x] E1/E2 pure QR export codec and tests
- [x] E3 confirmation and ephemeral view
- [ ] E4 local/CI verification and checkpoint

Local JUnit 16/16 (single/batch/QR import/export), 11 unique Python source contracts, AAPT2 resources PASS, actual Kotlin-generated synthetic envelope -> existing iOS Swift parser PASS, git diff --check PASS. Existing iOS QR warning translations reused for 12 locale sets; English fallback explicitly supplied for the remaining sets. No physical UI/transfer or full Gradle CI acceptance yet. No camera changes or production release.
