# Native profile and encrypted backup review rehearsal

The app has an explicitly gated `DEBUG && APL_NATIVE_PROFILE_REVIEW && targetEnvironment(simulator)` QA screen reachable from the backup sheet. The default project does not define this flag. The English QA labels are deliberate, not final product localization. No shipping UI, product profile model, real Keychain, VPN, CloudKit, or entitlements are changed.

`NativeProfileReviewSession` owns its own ephemeral memory catalog and records. It reuses the native compiler, single-use review and journaled additive restore contract. The rehearsal's injected inactive guard is true because it owns no VPN object; it is never a valid OS check for a real restore. Imported text is bounded, displayed results contain only per-protocol counts and backup export receives authenticated ciphertext only. A failed preview, cancel, or expired confirmation cannot commit; closing the sheet clears memory references. This does not promise secure zeroization. The original storage-bound user flow still needs exclusive real OS coordination, signed cross-process Keychain and UI acceptance.

Verified Swift Core 351/351 (four new session tests including all three protocols in one encrypted backup, independent restore, wrong password, cancellation, expiry and cleanup), full iOS Python 413/413 plus 1527 subtests, explicit simulator Debug build. The simulator app UI was not launched, so Files picker interaction, visual layout, actual sheet lifecycle and export destination behavior remain unaccepted. No physical iPhone action.

Default unsigned Release build also PASS; simulator QA entry string and native engine symbols absent from shipping executables.
