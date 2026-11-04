# iOS QR sharing: physical system share-sheet attestation (4 November 2026)

## Verified on a paired iPhone

Paired iPhone 13, iOS 27.2, ARC only. The production App Store APL 0.1.41 (build 46) remained installed before and after the test. We built and signed a separate QA app (ru.arvectum.qrdeviceqa.device), with no App Group, no PacketTunnel/NetworkExtension entitlements, and a fake .invalid proxy profile. No production profile, Keychain, active VPN, Apple review or real remote proxy was accessed.

With the explicit QA launch flag -aplQASystemShareAttestation, the independent app:
1. Executed the actual production QR encoder/rasterizer and strict receiver parser on synthetic SOCKS5 with Unicode and special-character credentials: PASS.
2. Presented the actual UIKit UIActivityViewController with a QR UIImage and import-link string. Recorded only the viewDidAppear lifecycle callback: PASS.
3. Checked physical camera hardware availability and current camera authorization status *without* requesting permission, starting a capture session, or collecting a camera frame.
4. Saved only status booleans/labels in its own Documents sandbox; the non-sensitive JSON was read using devicectl device copy from. No contact suggestions, personal screen captures or real credentials were collected.

Device evidence:

    result: PASS
    apple_activity_view: presented
    camera_hardware: available
    camera_permission: not_requested
    external_share: not_performed
    details: PASS: QR pixels decoded and profile matched on hardware
    device: iPhone
    os_version: 27.2
    bundle_id: ru.arvectum.qrdeviceqa.device
    date: 2026-11-04T13:24:46Z

The QA app was uninstalled immediately after evidence extraction. The production APL 0.1.41 (46) remained installed and untouched.

## Honest limitations and remaining release gates

This attests a real system Share Sheet appeared on physical iOS in a *separate synthetic QA app*. It does not prove the user tapped the production APL Share button. No actual recipient was selected, no AirDrop/Messages transfer occurred, camera permission was not requested, camera scanning from a second screen was not performed, and a second iPhone did not import the profile. VoiceOver and the Apple-distributed 0.1.41 to 0.2.0 Keychain migration remain unverified.

Xcode physical XCTest UI Automation continues failing before assertions with XCTFuture 1000 on both installed Xcode 27.1 and 27.2; an out-of-date CoreSimulator service was logged on the latter. This independent in-app lifecycle proof bypasses XCTest without modifying shared developer services.

## Reproduction

Generate the independent QA Xcode project from mobile/ios/HardwareQA/QRDeviceQA/project.yml, sign for physical iPhone, and install ONLY ru.arvectum.qrdeviceqa.device. Launch through devicectl device process launch using -- before the -aplQASystemShareAttestation app argument. Confirm result PASS, apple_activity_view presented, and external_share not_performed from the QA app's own Documents/qr-hardware-evidence.json. Uninstall only the QA app and read-only verify production APL version unchanged.

## Verification runs

Swift Core 159/159 PASS; iOS Python source and localization 119 run, one skipped, no failures; five targeted QA isolation tests PASS; signed physical iPhoneOS QA build PASS; no App Group/NetworkExtension entitlements; source diff check PASS.
