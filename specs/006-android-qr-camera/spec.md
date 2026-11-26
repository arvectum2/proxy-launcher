# APL-ANDROID-QR-CAMERA-20261126
- C1: explicit in-app scanner, rear camera only, optional CAMERA permission requested on user action; device without camera/permission denied must retain image and TXT import.
- C2: bounded YUV luminance input (max 1280x960 or equivalent 1,228,800 pixels), handle row/pixel stride; no frame persistence, network or credentials in logs. QR-only decode via already pinned ZXing; one decoded supported QR, same iOS envelope and parser.
- C3: camera and capture resources released on pause, cancellation, configuration change or successful result; no stale callback can deliver a second result. No automatic VPN or persistence; existing disconnected-only preview and explicit Save remain sole boundary.
- C4: synthetic frame and lifecycle tests, Android build/lint; actual camera grant/deny, portrait/landscape, cancellation and cross-device scan acceptance separately. No release/version/signing change.
