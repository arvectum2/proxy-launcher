# APL — editorial QA and Tier-3 language drafts (30 October 2026)

## Source of translations

The active 40-language baseline is unchanged in membership. The final ten Tier-3 languages are being authored directly with ChatGPT's multilingual text-generation/editorial capabilities and written through ARC to the repository. **ARC is the transport to the source checkout, not a translation engine.** This stage did not call Google Translate, MyMemory, Qwen or another runtime translation service. ChatGPT does not use discrete downloadable language packs.

## Completed in this editorial wave

1. Audited the 40 complete iOS/Android/desktop catalogs: **155 + 104 + 193 = 452 source keys per locale, 18,080 localized UI entries overall**. Corrected Android BCP-47 script-specific Chinese resource paths in the independent audit. The repeat scan now reports zero identical, long multiword English UI messages in non-English production locales. This is a lexical screening method, **not a guarantee of semantic correctness**.
2. Removed four untranslated long English messages from Uzbek desktop: network system proxy enabled with `%s`, external-proxy prerequisite, and both imperative variants of host/IP/port/login/password instruction. Retained `%s` and trailing join whitespace.
3. Corrected French Android VPN-disabled message left in English.
4. Inspected desktop Windows autorun removal call-site in `proxy_gui.py` before editing: its warning says that **other apps' autostart registry entries are untouched**, not “other people's records” and not “other programs' network settings.” Rewrote that one critical warning across **all 40 active language catalogs** (including English and Russian) with each locale's exact Log action label. Preserve original Russian source lookup key and leading `\n\n` concatenation boundary.
5. Authored ten Tier-3 glossaries (`ha`, `am`, `sv`, `da`, `fi`, `nb`, `bg`, `sr`, `hr`, `ca`): **28 technical terms × 10 languages = 280 reviewed draft terms** in `localization/drafts/tier3-glossary.json`.
6. Authored 16 complete high-impact iOS instructional texts per Tier-3 language (**160 editorial drafts**) in `localization/drafts/tier3-critical-ios.json`: app-open/close automations, adding exclusions, direct domain rules, reconnecting VPN, iOS permission, profile configuration and protocol, normal-on/off modes, system limitation and VPN reactivation. Preserved APL, HTTP/HTTPS/SOCKS5, VPN, host:port, IP and the exact `gosuslugi.ru` and `gu-st.ru` examples.
7. Used Latin Hausa, Ethiopic Amharic, Serbian Cyrillic and Latin Croatian deliberately. For languages not supported by the user's iOS system locale, Shortcuts action labels remain English **where not verified against an Apple on-device translation**.

## Validation and honesty gate

- Source review scripts and focused regression tests: `tests/test_editorial_english_leaks.py`, `tests/test_tier3_editorial_drafts.py`.
- Drafts are **not installed in the app** and do **not** count as completed user-visible localization. Full 10 × 452 source translations, 10 platform-specific picker/locale qualifiers, native proofreading and on-device overflow/accessibility checks are still required before the total can be marked 50/50.
- A model can perform multilingual editorial rewriting but cannot truthfully certify a professional independent native-speaker review. Do not represent this draft as a completed independent native-speaker proofread.
- Apple App Store Connect privacy/metadata, submitted build and disabled Watchdog were not changed. No fake English catalogs, no Apple release submission, no automatic merge.

## Resume work

Fill the remaining English source values natively in each of ten locales using `localization/drafts/` as the approved technical/style memory. Run full per-platform source equality/placeholder tests and iOS/Android build tests, then complete a second semantic review of network recovery, autostart, and app permissions. Promote drafts only after complete. Continue from `.agent/current-task.yaml` in the checkout; avoid repeating already reviewed 40 production locales.
