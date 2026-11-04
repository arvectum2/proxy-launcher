import AVFoundation
import SwiftUI

final class ProxyCameraPreviewController: UIViewController {
    var previewLayer: AVCaptureVideoPreviewLayer?
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}

/// Stable, privacy-safe failures for localized QR camera feedback.
/// Never pass native AVFoundation error descriptions into the user interface.
enum ProxyQRScannerFailure: Equatable {
    case permissionDenied
    case cameraUnavailable
    case inputUnavailable
    case outputUnavailable
    case startFailed

    var localizationKey: String {
        switch self {
        case .permissionDenied: return "Нет доступа к камере"
        case .cameraUnavailable: return "Камера недоступна"
        case .inputUnavailable: return "Не удалось открыть камеру"
        case .outputUnavailable: return "Не удалось запустить сканирование"
        case .startFailed: return "Не удалось запустить сканирование"
        }
    }

    var needsCameraSettings: Bool { self == .permissionDenied }
}

struct ProxyQRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (ProxyQRScannerFailure) -> Void
    let onReady: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError, onReady: onReady) }
    func makeUIViewController(context: Context) -> ProxyCameraPreviewController {
        let controller = ProxyCameraPreviewController()
        controller.view.backgroundColor = .black
        let coordinator = context.coordinator
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted { coordinator.configure(in: controller) }
                else { coordinator.fail(.permissionDenied) }
            }
        }
        return controller
    }
    func updateUIViewController(_ controller: ProxyCameraPreviewController, context: Context) {}
    static func dismantleUIViewController(_ controller: ProxyCameraPreviewController, coordinator: Coordinator) {
        coordinator.cancel()
    }
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String) -> Void
        let onError: (ProxyQRScannerFailure) -> Void
        let onReady: () -> Void
        var session: AVCaptureSession?
        private let captureQueue = DispatchQueue(label: "ru.arvectum.apl.qr.capture", qos: .userInitiated)
        private var finished = false
        init(onCode: @escaping (String) -> Void, onError: @escaping (ProxyQRScannerFailure) -> Void, onReady: @escaping () -> Void) {
            self.onCode = onCode; self.onError = onError; self.onReady = onReady
        }
        func fail(_ reason: ProxyQRScannerFailure) {
            guard !finished else { return }
            finished = true
            onError(reason)
        }
        func cancel() {
            finished = true
            if let capture = session {
                captureQueue.async {
                    if capture.isRunning { capture.stopRunning() }
                }
            }
        }
        func configure(in controller: ProxyCameraPreviewController) {
            guard !finished else { return } // Permission may be granted after dismissal.
            guard session == nil else { return }
            guard let device = AVCaptureDevice.default(for: .video) else {
                fail(.cameraUnavailable); return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                let capture = AVCaptureSession()
                guard capture.canAddInput(input) else { fail(.inputUnavailable); return }
                capture.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard capture.canAddOutput(output) else { fail(.outputUnavailable); return }
                capture.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                let preview = AVCaptureVideoPreviewLayer(session: capture)
                preview.videoGravity = .resizeAspectFill
                preview.frame = controller.view.bounds
                controller.view.layer.addSublayer(preview)
                controller.previewLayer = preview
                controller.view.setNeedsLayout()
                session = capture
                captureQueue.async {
                    capture.startRunning()
                    let running = capture.isRunning
                    DispatchQueue.main.async {
                        guard !self.finished else { return }
                        if running { self.onReady() }
                        else { self.fail(.startFailed) }
                    }
                }
            } catch { fail(.inputUnavailable) }
        }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !finished, let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            finished = true
            onCode(code)
        }
    }
}
