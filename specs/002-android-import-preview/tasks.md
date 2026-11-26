# Tasks
- [x] Reconcile prior roadmap, iOS Apple and RuStore evidence.
- [x] A1/A2/A4 parser + negative tests.
- [x] A3 editor preview and localized messages (source; physical UI pending).
- [ ] A5 run tests/build/lint; record hardware gate.
- [ ] A6 PR/checkpoint; no release.

Local: Kotlin 2.0.21 JVM compilation + JUnit 4/4 PASS; 2 source/resource contract tests PASS; AAPT2 all resources PASS; 40 locale resource sets (editorial translations, not native-speaker verified). No connected Android hardware. Exact Gradle 8.9 absent locally; use existing Android CI. Do not mark application build or device acceptance PASS until verified.
