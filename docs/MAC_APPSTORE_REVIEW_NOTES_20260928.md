# Mac App Store Review Notes — 0.2.17 build 3

This build addresses the previous rejection under Guidelines 2.1.0 and 2.4.5.

For Guideline 2.1.0:
- The app no longer creates, enables, or saves a Network Extension configuration during normal app launch.
- The VPN configuration is only created or modified after the user explicitly presses Connect.
- We verified this behavior on a physical Mac: launching the app without pressing Connect did not create an additional VPN configuration.
- Store help no longer links to GitHub Releases; updates for this build are delivered through the Mac App Store.

For Guideline 2.4.5:
- The Mac App Store build is Apple-silicon-only (arm64).
- The minimum supported macOS version is now 13.0 in both the main app and the embedded Packet Tunnel extension.
- The app and extension are sandboxed and use the Network Extension packet-tunnel entitlement.
- The package was built with Xcode 27 and Apple server validation completed with no errors.

Reviewer steps:
1. Launch Arvectum Proxy Launcher.
2. Add or select a proxy profile.
3. Press Connect. macOS may request permission to add the VPN configuration at this point.
4. Confirm the status changes to Connected.
5. Press Disconnect to stop the tunnel.

Build 3 is the corrected build for review. Please do not use build 2; build 2 retained a macOS 12.0 minimum system version.
