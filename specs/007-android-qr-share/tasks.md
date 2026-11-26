# Tasks
- [x] S1/S3 consent and chooser (source implementation)
- [x] S2 bounded memory provider and grant lifecycle
- [ ] S4 full Android CI, protected merge and separate device gate

Local: JUnit 23/23 (including expiry, replacement, bounded random-access reads and process death), 17 unique Python source contracts, provider Kotlin compile against API35, AAPT2 all resources and git diff check PASS. Actual OS grant/chooser/recipient and open descriptor expiry not tested on device. Revocation cannot retract copied or OS-cached data. Warning localized to Russian/English/German/French/Spanish, English fallback for remaining sets. No production release.
