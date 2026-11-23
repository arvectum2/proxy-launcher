# APL iOS 0.3.0(49) — exact signed native candidate, 23 November 2026

Source commit: 5c2d5554652aed38b993d3ede1f1ee0a10a51f3b, clean PR #383 source; exact current Swift and support sources copied and hash-verified into independent staging with prior native release recipe. No main, existing profiles or service changes.

Private signed artifact directory:
/Volumes/ArvectumSSD/Arvectum/worktrees/proxy-launcher/native-artifacts/ios-030-release-candidate-20261123-final-5c2d5554

Native Release flags: app provider-integration, persistent library, product-runtime, exact-DNS; PacketTunnel unified Go, Xray, AWG and bridge. Static reviewed Go SHA256 45716d42d434ae6d6576d9a32f47a4ea63d4943f106cb3bb7e6af57c725ea7af; Rust SHA256 6aea76be103f0266c54d10e049f6b9a231cc8ccaf25c59c89003bafe61b2ae16.

Signed archive APL-0.3.0-49-native.xcarchive PASS, both app and PacketTunnel code signatures. Native AppStore IPA SHA256 eb079c392f3ab295d9e9a26b788b4792ee3758701a888a2832edaf3be62abe94. Native Development IPA SHA256 71606f85c1f8edff86175498b82dda4b4ad4af32ba5d72a101d0687e03ef875e. Both extracted independently, validated version 0.3.0(49), arm64, correct Apple signatures, profiles, App Group, matching app/provider Mach-O UUID between variants, on-device development provision, retained YandexMobileAds and native manager phase markers. See native-signed-ipa-verification.json in private artifact. GitHub exact-source CI passes all checks; Swift431 and Python353+14 subtests PASS.

Not installed, uploaded or published. Physical iPhone13 remains paired with current older QA installation. Read-only last App Group event is CONNECTED with no later DISCONNECTED; a dark screenshot cannot establish OS VPN status. Do not interrupt or reinstall until owner manually unlocks device, disconnects any active VPN and confirms in-place Development QA.

After that action: preserve 3 legacy profiles and 1 WG; verify new signed legacy connect/off, actual native WG/AWG manager state and exact DNS/IPv6/UDP independent peer witnesses, restore original selection and terminal OS VPN OFF. VLESS connection remains fail-closed; CloudKit live two-device remains a distinct feature gate. PR #383 currently targets an intermediate QA branch rather than main; do not merge or submit until explicit release acceptance.

A separate standard Release build without native product runtime under /Users/master/Arvectum/releases/APL-ios-030-49-5c2d5554-20261123 is NOT the selected shipping artifact.

Main integration dry-run: 23 Nov git merge-tree reports one documentation conflict in docs/APL_ACTIVE_IOS_ROADMAP_2026-11-11.md; no code merge conflict was reported. Main carries new Spec Kit acceptance review. Resolve by preserving both documents before merging a release branch; leave main untouched now.
