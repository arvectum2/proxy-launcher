# Tasks
- [x] P1 bounded encrypted catalog (source and JVM crypto tests)
- [x] P2 saved-source UI and explicit refresh (source)
- [x] P3 guarded additive review
- [ ] P4 full Android CI, protected merge and separate device gate

Local: JVM 41/41 including 5 new saved-source crypto/review methods, 27 unique Python source contracts, SecureSubscriptionStore compile against API35, AAPT2 all resources and git diff check PASS. Android Keystore persistence/fault injection and real provider/UI not verified. The catalog permits up to 12 distinct source IDs, display host plus ordinal (no custom title), URL encrypted with a distinct device key. UI warning translations ru/en/de/fr/es, English fallback elsewhere. Existing profile passwords/selection are not modified; managed ownership, replacement and rollback remain a separate milestone. No release.
