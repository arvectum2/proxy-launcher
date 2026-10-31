import AVFoundation
import SwiftUI

struct ProxyQRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError) }
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
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
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        if let session = coordinator.session {
            DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
        }
    }
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String) -> Void
        let onError: (String) -> Void
        var session: AVCaptureSession?
        private var finished = false
        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onCode = onCode; self.onError = onError
        }
        func configure(in controller: UIViewController) {
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
                session = capture
                DispatchQueue.global(qos: .userInitiated).async { capture.startRunning() }
            } catch { onError(error.localizedDescription) }
        }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !finished, let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            finished = true
            onCode(code)
        }
    }
}
