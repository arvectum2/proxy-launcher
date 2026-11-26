# Tasks
- [x] C2 bounded luminance adapter and tests
- [x] C1/C3 permission/lifecycle UI and preview integration (source and API-level compile)
- [ ] C4 full Android CI and separate device acceptance

Local checks: Kotlin 2.0.21 JVM 19/19, including strided synthetic QR frames; native scanner class compiled against API 35 with resource ID stub; 14 unique Python source contracts; AAPT2 all resources PASS; 40 complete camera string sets reused from iOS. No physical camera session or complete Android build claimed. Parent PR390 passed 15/15 after mirror retry, merged bf443090.
