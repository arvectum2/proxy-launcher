# iOS 0.3.0 native VLESS Reality — isolated SOCKS witness and fingerprint differential, 23 Nov 2026

Full release still requires accepted native VLESS/Reality egress. The UI reporting Connected is not sufficient and the product release is NOT accepted.

## Physical iPhone13, signed source 4f1788a0, synthetic r15

- Stopped originally active legacy Основной through normal APL UI. Imported, selected and started one throwaway VLESS Reality profile. Actual PacketTunnel PID79516; native product UI showed connected.
- Independent signed QA-only app without NetworkExtension connected to the actual iOS local Xray SOCKS5 loopback port 39879. Private receipt native-artifacts/ios-030-vless-direct-socks-r15-20261123/client-result.json: greeting=true, connect=true, receipt=false; run ID matched.
- Safari HTTP challenge also failed. Independent pinned Xray Reality server positive control PASS, then 7 iPhone TCP connections, 15889 inbound bytes, 16835 outbound bytes, app-layer nonce witnessCount=0.
- Thus local iOS SOCKS5 listener and SOCKS CONNECT are live, physical Reality TCP sockets open, but application HTTP egress and response are not accepted. This does not isolate iOS TUN routing separately: direct loopback SOCKS already failed.

## Pinpoint Mac fingerprint controls; NO Firefox iPhone result

- Matching-version pinned Xray Mac CLI with full source-equivalent Chrome-fingerprint profile and en0 socket binding had previously produced exact HTTP witness.
- Separate private ios fingerprint test r16 failed its pinned local positive-control preflight. No iPhone test run for that variant.
- Separate private firefox fingerprint test r17 passed pinned local positive preflight and Mac CLI with identical Xray core and en0 socket binding received the exact HTTP nonce. Independent server accepted TCP1, witnessCount1.
- Firefox is a candidate for ONE controlled iPhone confirmation, not an established compatibility fix. Do not silently alter a user's profile fingerprint.

## Terminal state verified

- Both independent QA servers ended, no TCP QA listeners. Signed production APL 0.3.0(49) source178eb560 installed again; original signed HTTPSWitness restored.
- Temporary native VLESS profile removed, only original WireGuard 8BFC7731 and 3 legacy profiles preserved, selected and reconnected original legacy Основной (OS PacketTunnel PID79691). Clipboard blank.
- No Apple profile/entitlement/App ID changes; user explicitly refused them. No Apple upload, main merge or publication. CloudKit automatic signed sync cannot be claimed without entitlement.

Next focused task: ONE bounded Firefox physical synthetic profile test with independent HTTP receipt before production enablement; otherwise investigate iOS libXray uTLS handshake with scoped metadata. Do not rerun completed WireGuard QA.
