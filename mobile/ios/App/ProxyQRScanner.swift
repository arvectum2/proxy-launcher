import AVFoundation
import SwiftUI

final class ProxyCameraPreviewController: UIViewController {
    var previewLayer: AVCaptureVideoPreviewLayer?
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}

struct ProxyQRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void
    let onReady: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError, onReady: onReady) }
    func makeUIViewController(context: Context) -> ProxyCameraPreviewController {
        let controller = ProxyCameraPreviewController()
        controller.view.backgroundColor = .black
        let coordinator = context.coordinator
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted { coordinator.configure(in: controller) }
                else { coordinator.onError("Нет доступа к камере") }
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
        let onError: (String) -> Void
        let onReady: () -> Void
        var session: AVCaptureSession?
        private let captureQueue = DispatchQueue(label: "ru.arvectum.apl.qr.capture", qos: .userInitiated)
        private var finished = false
        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void, onReady: @escaping () -> Void) {
            self.onCode = onCode; self.onError = onError; self.onReady = onReady
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
            guard session == nil, let device = AVCaptureDevice.default(for: .video) else {
                onError("Камера недоступна"); return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                let capture = AVCaptureSession()
                guard capture.canAddInput(input) else { onError("Не удалось открыть камеру"); return }
                capture.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard capture.canAddOutput(output) else { onError("Не удалось запустить сканирование"); return }
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
                    if capture.isRunning {
                        DispatchQueue.main.async {
                            if !self.finished { self.onReady() }
                        }
                    }
                }
            } catch { onError(error.localizedDescription) }
        }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !finished, let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            finished = true
            onCode(code)
        }
    }
}
