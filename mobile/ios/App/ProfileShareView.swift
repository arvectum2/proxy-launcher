import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Share is an explicit user action. This screen builds a credential-bearing
/// QR entirely on device and keeps its contents only in ephemeral view state.
struct ProfileShareView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let profile: ProxyProfile

    @State private var link: URL?
    @State private var qrImage: UIImage?
    @State private var showAppleShareSheet = false
    @State private var failed = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    Text(profile.name)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(ProfileShareUX.text("QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете."))
                        .font(.footnote)
                        .foregroundStyle(Brand.softGray)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300)
                            .padding(14)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel(ProfileShareUX.text("Поделиться профилем"))
                            .accessibilityIdentifier("profiles.share.qrImage")
                        Button {
                            showAppleShareSheet = true
                        } label: {
                            Label(ProfileShareUX.text("Отправить QR-код"),
                                  systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("profiles.share.systemSheet")
                        .disabled(link == nil)
                    } else if failed {
                        Text(ProfileShareUX.text("Не удалось создать QR-код"))
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("profiles.share.error")
                    } else {
                        ProgressView()
                    }
                }
                .padding(20)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle(ProfileShareUX.text("Поделиться профилем"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ProxyImportUX.text("Закрыть")) { dismiss() }
                }
            }
            .onAppear(perform: prepare)
            .sheet(isPresented: $showAppleShareSheet) {
                if let link, let qrImage {
                    ProfileShareActivity(items: [qrImage, link])
                }
            }
        }
    }

    private func prepare() {
        guard link == nil, !failed else { return }
        do {
            // Read this *specific* profile's password from Keychain, only
            // after its own Share button was tapped.
            let newLink = try model.shareLink(for: profile)
            guard let image = ProxyShareQRRenderer.render(newLink) else {
                failed = true
                return
            }
            qrImage = image
            link = newLink
        } catch {
            // Never display raw Keychain or proxy error strings.
            failed = true
        }
    }
}

private enum ProxyShareQRRenderer {
    static func render(_ link: URL) -> UIImage? {
        guard link.absoluteString.utf8.count <= ProxyShare.maxLinkBytes else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

private struct ProfileShareActivity: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
