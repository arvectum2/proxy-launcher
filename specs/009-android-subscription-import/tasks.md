# Tasks
- [x] S1 URL/address policy and network transport (source, synthetic tests)
- [x] S2 body decoding and regression tests
- [x] S3 explicit UI/lifecycle and preview (source)
- [ ] S4 full CI, integration and device gate

Local: 36/36 JVM tests, 23 unique Python source contracts, AAPT2 all resources, git diff check PASS. OkHttp 4.12.0/Okio JVM 3.6.0 cached JAR SHA-1 verified against Maven Central, SHA-256 pinned, licenses packaged. No actual HTTPS/DNS/TLS or device lifecycle test, no comprehensive dependency vulnerability audit. Five translated UI variants, English fallback elsewhere. URL never deliberately persisted; manual append-only import, no managed replacement, saved URL or background refresh. No real supplier traffic or production release.
