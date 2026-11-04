import SwiftUI
import UIKit

/// Only used by the separately signed synthetic QR hardware QA application.
/// Presents the exact UIKit activity API used by ProxyShareView; never invokes
/// any activity, recipient, third-party app or network transfer.
struct QRSystemShareAttestation: UIViewControllerRepresentable {
    let onPresented: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Exact production codec and rasterizer, fake .invalid destination.
        let fixture = ProxyProfile(name: "Тестовый QR", host: "share-qa.invalid",
                                   port: 1080, type: .socks5, username: "qa:test")
        // Validated by the production sender, not an invented mock link.
        let url = try? ProxyProfileSharing.deepLink(profile: fixture, password: "fake-%25")
        let image = url.flatMap { try? ProxyShareQRCode.image(for: $0) }
        guard let url, let image else {
            // Fail closed; onPresented will not be called for a controller
            // without a validated synthetic QR payload.
            return QAAttestedActivityController(activityItems: [], applicationActivities: nil)
        }
        let controller = QAAttestedActivityController(
            activityItems: [image, url.absoluteString],
            applicationActivities: nil)
        controller.onPresented = onPresented
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    private final class QAAttestedActivityController: UIActivityViewController {
        var onPresented: (() -> Void)?
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onPresented?()
            onPresented = nil
        }
    }
}
