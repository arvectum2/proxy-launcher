# Android dogfood signing

`proxy-launcher-dogfood.keystore` is an intentionally non-secret, non-production signing identity for local/CI dogfood builds.

- alias: `androiddebugkey`
- store/key password: standard Android debug value `android`
- certificate SHA-256: `FD:57:CD:46:AD:1E:54:A1:53:AA:9E:D5:6B:4B:BB:63:0B:33:01:5E:23:D4:C6:A8:60:77:A6:7C:F0:E2:83:13`

Purpose: keep dogfood signer identity stable across clean CI runners so a newer dogfood APK can update the previous stable-signed one.

Do not use this key for production, Play, RuStore, enterprise distribution, or any build whose signing identity is expected to be private.
Production signing must use a separately protected key and release process.
