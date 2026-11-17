# Isolated physical HTTPS witness

Separate app identifier `ru.arvectum.proxylauncher.lab.httpswitness`, no App Group, shared Keychain or VPN entitlement. The two HTTPS requests use ephemeral sessions and no redirects or caches. httpbingo validates a fresh nonce; ipify provides an independent IP response. Only status and a per-run salted origin digest are stored. A before/on/after run with the same UUID compares direct and tunneled observations. No user credentials or raw IPs are emitted. The witness is never embedded in release builds.
