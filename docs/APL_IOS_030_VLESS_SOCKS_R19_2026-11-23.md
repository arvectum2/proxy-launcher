# iOS 0.3.0: Physical VLESS Reality firefox fingerprint r19 (23 November 2026)

- Previous r18 synthetic server expired with zero iPhone connections because the device test was NOT attempted; its zero result is inconclusive.
- For actual physical r19, iPhone13, signed source 4f1788a0: imported synthetic VLESS Reality fp=firefox and selected it while legacy Основной was stopped in APL UI. Native PacketTunnel PID 79751 launched and UI showed connected.
- Safari exact HTTP challenge to 198.51.100.77:39883 through the active tunnel failed, displaying interrupted connection.
- Pinned independent Xray Reality server positive control passed. Terminal observation: relayAccepted=7 TCP, ingressBytes=0, egressBytes=0, witnessCount=0. NO application HTTP receipt. This is a real iPhone VLESS failure, not release acceptance.
- Earlier Mac Xray 26.11.9 with same Firefox fingerprint and en0 binding r17 passed precise HTTP challenge with independent witnessCount=1. Changing the fingerprint alone therefore does NOT fix iOS.
- Independent no-NetworkExtension SOCKS QA app installed; its iOS launch was denied by system code-signature/developer trust while synthetic broken VPN was active. Thus NO physical r19 direct-SOCKS result. Original previously trusted QA app launched under restored working VPN; in future preflight the diagnostic app BEFORE disrupting connectivity rather than changing Apple profiles.
- Terminal restoration: stopped peer/server and all test listeners, removed ONLY synthetic VLESS profile, reselected original WireGuard 8BFC7731, reinstalled original signed APL 0.3.0(49) and HTTPSWitness, preserved 3 legacy profiles. Cleared test clipboard and overwrote synthetic QA input with zero bytes. Selected and reconnected original Основной; iOS PacketTunnel PID 79818.
- No Apple Developer profile/entitlement/App ID modifications, no PR merge or App Store upload.

Next: inspect embedded iOS libXray TLS/REALITY ClientHello versus physical interface binding. Only another carefully instrumented test with newly available diagnostics would be justified; no blind fingerprint loops. Candidate upstream symptom references, not proof of matching root cause: https://github.com/XTLS/Xray-core/issues/5908 and https://github.com/XTLS/libXray/issues/116 .
