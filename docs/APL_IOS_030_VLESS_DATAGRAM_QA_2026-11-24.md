# Full-route protocol QA candidate — 24 November 2026

Owner deferred diagnosis of the original Основной proxy. Product provider PID84658 observed active before offline preparation; no device mutation, profile changes or VPN interruption performed.

Extended the separate full-route QA target with fixed enumerated TCP4/TCP6/UDP4/UDP6 tuples. The local Xray blackhole default remains first, with only one exact IP/network/39883 rule for the chosen run. Provider requires explicit witness kind and host acceptance checks the matching kind receipt. IPv6 uses an unbound AF_INET6 socket; UDP uses one connected socket, one nonce datagram, six-second deadline and exact response, no retry or DNS lookup. Existing scoped build retains TCP4 mode. No production target changes or public enablement.

ARM64 compilation and strict existing local development signatures passed. Signed artifact native-artifacts/ios-030-provider-full-route-datagrams-signed-20261124/NativeLabHost.app. Host SHA256 59190188b6659b7f2ef0b3770d476110f3170c96d4414530941311c4f496d415; extension SHA256 8f7170c709513cd8bba71f9ea009d2925e02b35761c186b31c4a29bbcedff7c9. 22 focused Python tests, 50 release contract tests, 15 witness parser/protocol checks, 14 guard checks, release preflight PASS. Previous exact head eadf6c9c all six CI checks successful.

Independent Mac reference preflight-only TCP6, UDP4, UDP6 all passed using existing pinned peer, fresh synthetic VLESS key fixture (generator's TCP4 key material only) and explicit vlessDatagrams protocol command. Temporary directories removed and no TCP listeners on QA ports after preflight. This is local reference control, not physical iPhone acceptance.

Next: once owner VPN is off or its interruption separately authorized, install existing signed candidate, inspect ownership, prepare one owned lab manager per run; run three separate cases using the matching vlessDatagrams command and host probeKind. Require independent exact challenge/response hash, correct witness kind, receipt and native stop/drain, cleanup. Restore prior lab binary and original device state. Do not repeat accepted TCP4. DNS, wrong-key/peer-loss, WAN/leak and product acceptance remain pending. No diagnosis of Основной, publication or Apple changes.

## Physical acceptance, 18:52 local time

Owner explicitly authorized interruption for all three trials. Actual baseline already OFF, selected Нидерланды 2, provider absent, so no disconnection was needed. Original Основной diagnosis remains deferred at owner request. Installed the already signed QA candidate once. Automated runner initially rejected a misplaced launch option and then a 4-second devicectl timeout (minimum 5). Read-only census recovered; own cleanup confirmed; no traffic trials had started. Corrected option order and timeout to 10 seconds; resumed installed candidate without rebuilding or repeating any accepted trial. All action intents and results fsynced to private journal.jsonl.

| Probe | Run ID | Host bytes sent/received | Peer ingress/egress | Witnesses | Result |
|---|---|---:|---:|---:|---|
| tcp6 | A4F9AB5E-7B62-4DC9-B189-E934937904C6 | 102/160 | 2193/2635 | 1 | PASS |
| udp4 | B5207BA2-1000-427F-915C-DC92956EBFFE | 48/52 | 2200/2489 | 1 | PASS |
| udp6 | 908B9465-E5C5-498D-A993-21C0C166F684 | 48/52 | 2180/2489 | 1 | PASS |

Every run: full guarded routes, exact selected protocol, matching run ID and challenge/response hash, independent local peer positive control and one physical witness, complete first TLS record, matching descriptor, local SOCKS greeting, native Rust drain/Xray stop and own manager cleanup. UDP one datagram each direction, exact nonce response (legacy receipt field name hostExactHTTPReceipt is not an HTTP claim for UDP). Historical census identical before/after each case and final. Runner exit0; previous NativeLab 0.2.0(48) restored, synthetic private inputs scrubbed, no QA TCP listeners or UDP sockets, no provider active, product0.3.0(49) unchanged. Visual APL baseline restored: Нидерланды 2 selected and VPN OFF. Retained coarse evidence under native-artifacts/ios-030-datagrams-physical-20261124/{tcp6,udp4,udp6}-physical/correlated-receipt.json and journal.jsonl.

Full-route synthetic TCP4/TCP6/UDP4/UDP6 acceptance now complete. This is not unrestricted production or WAN, DNS, dynamic underlay or fail-closed/leak acceptance. Next isolated DNS positive witness and wrong-key/peer-loss negative controls. No public enablement or Apple changes.
