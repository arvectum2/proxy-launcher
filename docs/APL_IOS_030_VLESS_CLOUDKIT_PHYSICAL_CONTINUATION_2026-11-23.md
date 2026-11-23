# iOS full 0.3.0: VLESS underlay and CloudKit, 23 November 2026

The owner retains full VLESS/Reality and private iCloud manual-exclusions
sync in release 0.3.0. No partial release or Apple upload authorized.

Source 4f1788a0f22d09abbf0d305188b34dc02e48599b:
- Native Xray Reality validates and binds physical underlay via Darwin IP_BOUND_IF
  before full VPN routes; keeps production VLESS fail-closed until independent
  application-layer acceptance.
- A separate App-only CloudKit entitlement and opt-in --cloudkit staging
  exist; the PacketTunnel has no CloudKit entitlement.
- 435 Swift tests, 16 focused Python tests, and 50 iOS legacy release
  contract tests pass.
- Exact source --cloudkit unsigned ARM64 Release App+PacketTunnel builds:
  native-artifacts/ios-030-cloudkit-ready-4f1788a0-20261123. Its manifest
  explicitly records cloudkit_provisioned=false, release_authorized=false.
  Existing APL Apple Developer development/App Store profiles lack the
  container iCloud.ru.arvectum.proxylauncher.ios. Signed live two-device
  acceptance is NOT completed.

Bounded signed Apple Development QA-only VLESS on iPhone13:
- QA signed archive/IPA in private artifact
  native-artifacts/ios-030-vless-underlay-hardware-qa-4f1788a0-20261123.
- One synthetic VLESS Reality source was imported and selected, OS provider
  PID 78653 reached Connected; exact independent synthetic LAN peer r12
  accepted 7 TCP connections, 15465 bytes received and 16835 bytes sent.
- Safari's exact synthetic HTTP nonce request failed with a network
  interruption; server witnessCount 0. Physical socket underlay therefore
  works, but end-to-end VLESS application data remains NOT accepted.
- r11 was inconclusive before actual profile selection and is superseded.
- Restored original signed Development APL 0.3.0(49) from 178eb560,
  deleted only synthetic VLESS 11AB709E, retained original WG 8BFC7731 and
  three legacy proxies, reselected Основной, VPN OFF, cleared temporary
  clipboard, all test-server ports closed. No App Store submission.

Next: a pinned local protocol-level Xray config/handshake comparison to
isolate the data-plane failure BEFORE another hardware attempt; only enable
VLESS production after an independently accepted HTTP nonce receipt.
Apple App ID CloudKit capability, container, refreshed signed profiles and
private two-device acceptance remain necessary and involve external account
changes requiring separate approval. Preserve advertisements unchanged.
