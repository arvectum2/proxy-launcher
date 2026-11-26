# Isolated physical HTTPS witness

Separate app identifier `ru.arvectum.proxylauncher.lab.httpswitness`, no App Group, shared Keychain or VPN entitlement. The two HTTPS requests use ephemeral sessions and no redirects or caches. httpbingo validates a fresh nonce; ipify provides an independent IP response. Only status and a per-run salted origin digest are stored. A before/on/after run with the same UUID compares direct and tunneled observations. No user credentials or raw IPs are emitted. The witness is never embedded in release builds.

The optional `native-tcp4` mode is strictly a private fixture witness to TEST-NET-2 address `198.51.100.77:39883`, with an exact one-time response challenge. It never connects to a general-purpose relay.
