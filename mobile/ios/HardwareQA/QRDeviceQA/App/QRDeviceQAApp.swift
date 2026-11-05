import SwiftUI
import CoreImage
import UIKit
import AVFoundation

// Isolated QA bundle. Never accesses the installed APL App Group, Keychain
// or PacketTunnel, and never connects to a real proxy.
@main
struct QRDeviceQAApp: App {
    var body: some Scene { WindowGroup { QRDeviceQAHome() } }
}
enum AppL10n {
    static let effectiveLanguage = "ru"
    static func tr(_ key: String) -> String { key }
}
private enum Fixture {
    static let profile = ProxyProfile(name: "Тестовый прокси QR", host: "qr-device-qa.invalid",
                                      port: 1080, type: .socks5, username: "qa:user")
    static let password = "TEST-%25:пароль/@"
    static func link() throws -> URL {
        try ProxyProfileSharing.deepLink(profile: profile, password: password)
    }
}
struct QRDeviceQAHome: View {
    @State private var consent = false
    @State private var shared: ProxySharePresentation?
    @State private var scanning = false
    @State private var cameraReady = false
    @State private var preview: ImportedProxy?
    @State private var status = "NOT_RUN"
    @State private var qaActivityPresented = false
    @State private var qaActivityObserved = false
    @State private var smart4TransportStatus = "NOT_RUN"

    // Read-only camera hardware/authorization check. No permission prompt,
    // capture session, images or video frames are ever requested.
    private var cameraAvailability: String {
        AVCaptureDevice.default(for: .video) == nil ? "unavailable" : "available"
    }

    private var cameraAuthorization: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not_requested"
        @unknown default: return "unknown"
        }
    }

    private func writeSyntheticEvidence(_ outcome: String) {
        let payload: [String: String] = [
            "result": outcome.hasPrefix("PASS:") ? "PASS" : "FAIL",
            "details": outcome,
            "bundle_id": Bundle.main.bundleIdentifier ?? "unknown",
            "device": UIDevice.current.model,
            "os_version": UIDevice.current.systemVersion,
            "test": "real_iPhone_QR_image_CIDetector_and_strict_proxy_import",
            "date": ISO8601DateFormatter().string(from: Date()),
            "camera_hardware": cameraAvailability,
            "camera_permission": cameraAuthorization,
            "apple_activity_view": qaActivityObserved ? "presented" : "not_presented",
            "external_share": "not_performed"
        ]
        guard let directory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask).first,
              let encoded = try? JSONSerialization.data(
                withJSONObject: payload, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try? encoded.write(
            to: directory.appendingPathComponent("qr-hardware-evidence.json"),
            options: [.atomic])
    }

    private func selfTest() {
        defer { writeSyntheticEvidence(status) }
        do {
            let image = try ProxyShareQRCode.image(for: Fixture.link())
            guard let cg = image.cgImage,
                  let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                      context: CIContext(),
                      options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]),
                  let scanned = detector.features(in: CIImage(cgImage: cg))
                    .compactMap({ $0 as? CIQRCodeFeature }).first?.messageString else {
                status = "FAIL: QR pixels not decodable"; return
            }
            let data = try ProxyProfileSharing.scannedSource(scanned)
            let values = try ProxyImport.parse(data)
            guard values.count == 1, values[0].host == Fixture.profile.host,
                  values[0].name == Fixture.profile.name,
                  values[0].username == Fixture.profile.username,
                  values[0].password == Fixture.password,
                  values[0].type == .socks5 else {
                status = "FAIL: synthetic credential roundtrip"; return
            }
            status = "PASS: QR pixels decoded and profile matched on hardware"
        } catch { status = "FAIL: QR codec" }
    }

    private func reveal() {
        do {
            let link = try Fixture.link()
            shared = ProxySharePresentation(name: Fixture.profile.name,
                link: link, qrImage: try ProxyShareQRCode.image(for: link))
        } catch { status = "FAIL: QR generation" }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                Text("Только синтетический прокси .invalid")
                    .font(.headline)
                Text("Рабочая APL, VPN и профили не затрагиваются")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                if ProcessInfo.processInfo.arguments.contains("-aplSmart4PhysicalTransportQA") {
                    Text(smart4TransportStatus)
                        .font(.footnote.monospaced())
                        .accessibilityIdentifier("qa.smart4.transport-status")
                }
                Button("Проверить QR на iPhone") { selfTest() }
                    .accessibilityIdentifier("qa.run-selftest")
                Text(status).font(.footnote.monospaced())
                    .accessibilityIdentifier("qa.result")
                Button("Показать QR") { consent = true }
                    .accessibilityIdentifier("qa.open-share")
                Button("Сканировать камерой") {
                    cameraReady = false
                    scanning = true
                }.accessibilityIdentifier("qa.open-camera")
                if let value = preview {
                    Text("Предпросмотр: " + value.name)
                        .accessibilityIdentifier("qa.preview")
                    Button("Импортировать тестовый профиль") {
                        // Explicit one-action confirmation, intentionally no write.
                        status = "PASS: import confirmed without persistence"
                        preview = nil
                    }.accessibilityIdentifier("qa.confirm-import")
                }
                Spacer()
            }.padding()
                .navigationTitle("APL QR Device QA")
                .onAppear {
                    selfTest()
                    if ProcessInfo.processInfo.arguments.contains("-aplSmart4PhysicalTransportQA") {
                        Task {
                            smart4TransportStatus = await Smart4TransportPhysicalQA.run(
                                arguments: ProcessInfo.processInfo.arguments)
                            print("APL_SMART4_SYNTHETIC_TRANSPORT_RESULT " + smart4TransportStatus)
                        }
                    }
                    // Explicit synthetic-only CLI flag. Never used by the
                    // production app, and never invokes a third-party activity.
                    if ProcessInfo.processInfo.arguments.contains("-aplQASystemShareAttestation"),
                       status.hasPrefix("PASS:") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            qaActivityPresented = true
                        }
                    }
                }
                .sheet(isPresented: $qaActivityPresented) {
                    QRSystemShareAttestation {
                        // Proof of actual viewDidAppear, not delivery to any
                        // recipient or proof of the user's Apple share actions.
                        qaActivityObserved = true
                        writeSyntheticEvidence(status)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            qaActivityPresented = false
                        }
                    }
                }
                .confirmationDialog(
                    "QR раскрывает тестовый логин и пароль. Продолжить?",
                    isPresented: $consent
                ) {
                    Button("Подтверждаю показ") { reveal() }
                    Button("Отмена", role: .cancel) {}
                } message: { Text("Только фиктивный прокси .invalid") }
                .sheet(item: $shared) { ProxyShareView(item: $0) }
                .sheet(isPresented: $scanning) {
                    VStack {
                        Text(cameraReady ? "КАМЕРА ГОТОВА" : "ПОДГОТОВКА КАМЕРЫ")
                            .accessibilityIdentifier("qa.camera-status")
                        ProxyQRScanner(
                            onCode: { value in
                                scanning = false
                                do {
                                    let decoded = try ProxyProfileSharing.scannedSource(value)
                                    preview = try ProxyImport.parse(decoded).first
                                    status = preview == nil ? "FAIL: empty QR" :
                                        "PASS: camera decoded QR"
                                } catch { status = "FAIL: rejected QR" }
                            },
                            onError: { _ in status = "FAIL: camera unavailable" },
                            onReady: { cameraReady = true }
                        )
                        Button("Закрыть сканер") { scanning = false }
                            .accessibilityIdentifier("qa.close-camera")
                    }
                }
        }
    }
}
