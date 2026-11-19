#!/usr/bin/env python3
"""Build-copy-only adaptation of the containing runtime QA host to existing NativeLab IDs.
No production signing identities, app groups, associated domains or CloudKit are used.
"""
import pathlib
import plistlib
import sys

PRODUCT = "ru.arvectum.proxylauncher.ios"
LAB = "ru.arvectum.proxylauncher.lab.nativeqa"
TEAM = "VML75VY94V"
SHARED = TEAM + "." + LAB + ".shared"


def replace_once(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise ValueError(f"unexpected source shape: {path.name}")
    path.write_text(text.replace(old, new))


def stage(root):
    shared = root / "Shared/AppShared.swift"
    s = shared.read_text()
    assert s.count(PRODUCT) == 5 and TEAM + "." + PRODUCT + ".shared" in s
    shared.write_text(s.replace(PRODUCT, LAB))
    project = root / "project.yml"
    replace_once(project, "PRODUCT_BUNDLE_IDENTIFIER: " + PRODUCT + "\n", "PRODUCT_BUNDLE_IDENTIFIER: " + LAB + "\n")
    replace_once(project, "PRODUCT_BUNDLE_IDENTIFIER: " + PRODUCT + ".PacketTunnel\n", "PRODUCT_BUNDLE_IDENTIFIER: " + LAB + ".PacketTunnel\n")
    # NativeLab profiles have no application-group capability. Keep lab-only
    # defaults local to each process; the actual native handoff is Keychain.
    roots = ("App", "Shared", "SharedCore", "PacketTunnel")
    for folder in roots:
        for path in (root / folder).rglob("*.swift"):
            if path == shared:
                continue
            text = path.read_text()
            transformed = text.replace(PRODUCT, LAB).replace("UserDefaults(suiteName: AppShared.defaultsSuite)", "Optional(UserDefaults.standard)")
            if transformed != text:
                path.write_text(transformed)
    # Force the QA-only entry point, including launches from iPhone Mirroring.
    # No ordinary screen, subscription/cloud sync or advertising initialization.
    entry = root / "App/ArvectumProxyLauncherApp.swift"
    entry.write_text("""import SwiftUI
@main
struct ArvectumProxyLauncherApp: App {
    var body: some Scene {
        WindowGroup { NativeRuntimeReviewQAView() }
    }
}
""")
    harness = root / "App/NativeRuntimeReviewQAView.swift"
    replace_once(harness, 'ProcessInfo.processInfo.arguments.contains("-aplNativeRuntimeReviewQA")', "true")
    # Bounded, one-shot synthetic fixture preview from the lab's own container.
    # Mirroring's universal clipboard is not a reliable device input channel.
    library = root / "App/NativePersistentProfilesView.swift"
    replace_once(library, 'Button(tr("Import from clipboard","Импорт из буфера")){previewClipboard()}',
                 'Button(tr("Review staged lab fixture","Проверить тестовый файл")){previewClipboard()}')
    replace_once(library, 'guard let text=UIPasteboard.general.string else{throw NativeAutomaticImport.Failure.empty}\n            summary=try session.previewAutomatic([text])',
                 """let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("apl-nativeqa-fixture.txt")
            let attrs=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard attrs.isRegularFile==true,attrs.isSymbolicLink != true,let size=attrs.fileSize,(1...4096).contains(size) else{throw NativeAutomaticImport.Failure.unsupported}
            let text=try NativeAutomaticImport.readSource(url,limit:4096)
            let records=try NativeAutomaticImport.prepare([text])
            guard records.count==1,let record=records.first else{throw NativeAutomaticImport.Failure.unsupported}
            let endpoint=try record.endpointForEdit()
            let port:UInt16=record.reference.kind == .vlessReality ? 39882 : (record.reference.kind == .wireGuard ? 39881 : 39891)
            guard endpoint.host == "192.168.1.80",endpoint.port == port else{throw NativeAutomaticImport.Failure.unsupported}
            try FileManager.default.removeItem(at:url)
            summary=try session.previewTransfer(NativeImportTransfer(records))""")
    # Do not identify a production manager by its display name.
    manager = root / "App/VPNController.swift"
    replace_once(manager, 'private static let configurationName = "Arvectum Proxy Launcher"', 'private static let configurationName = "APL NativeLab (isolated)"')
    for name in ("App", "PacketTunnel"):
        path = root / "Config" / (name + ".entitlements")
        ent = {"com.apple.developer.networking.networkextension": ["packet-tunnel-provider"],
               "keychain-access-groups": [SHARED]}
        path.write_bytes(plistlib.dumps(ent))
        path = root / "Config" / (name + "-Info.plist")
        info = plistlib.loads(path.read_bytes())
        info["APLKeychainAccessGroup"] = SHARED
        info["CFBundleDisplayName"] = "APL NativeLab" if name == "App" else "APL NativeLab Tunnel"
        for key in ("CFBundleURLTypes", "UTExportedTypeDeclarations", "SKAdNetworkItems"):
            info.pop(key, None)
        path.write_bytes(plistlib.dumps(info))
    for folder in roots:
        assert all(PRODUCT not in p.read_text() for p in (root/folder).rglob("*.swift"))
    print("ISOLATED_NATIVEQA_SOURCE_STAGE_PASS", LAB)


if __name__ == "__main__":
    stage(pathlib.Path(sys.argv[1]))
