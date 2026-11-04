import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Prepared only after the sender confirms disclosure; never persisted.
struct ProxySharePresentation: Identifiable {
    let id = UUID()
    let name: String
    let link: URL
    let qrImage: UIImage
}

enum ProxyShareQRCode {
    static func image(for link: URL) throws -> UIImage {
        let payload = Data(link.absoluteString.utf8)
        guard !payload.isEmpty, payload.count <= 1800 else {
            throw ProxyImportError.tooLarge
        }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = payload
        filter.correctionLevel = "M"
        let context = CIContext()
        guard let generated = filter.outputImage,
              let encoded = context.createCGImage(generated, from: generated.extent) else {
            throw ProxyImportError.invalid
        }
        // Embed a white quiet zone in the actual exported image.
        let scale: CGFloat = 6
        let margin: CGFloat = 4 * scale
        let width = CGFloat(encoded.width) * scale + margin * 2
        let height = CGFloat(encoded.height) * scale + margin * 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: encoded).draw(in: CGRect(
                x: margin, y: margin,
                width: CGFloat(encoded.width) * scale,
                height: CGFloat(encoded.height) * scale))
        }
    }
}

struct ProxyShareView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showAppleShareSheet = false
    let item: ProxySharePresentation

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    Text(item.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Image(uiImage: item.qrImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: 320)
                        .accessibilityLabel(ProxyShareUX.text("QR-код для импорта прокси"))
                        .accessibilityAddTraits(.isImage)
                    Text(ProxyShareUX.text(
                        "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        showAppleShareSheet = true
                    } label: {
                        Label(ProxyShareUX.text("Отправить QR-код"),
                              systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("profiles.share.sendQR")
                }
                .padding(20)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(ProxyShareUX.text("Поделиться"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppL10n.tr("Закрыть")) { dismiss() }
                }
            }
            .sheet(isPresented: $showAppleShareSheet) {
                ProxyShareActivitySheet(items: [item.qrImage, item.link.absoluteString])
            }
        }
    }
}

private struct ProxyShareActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The QR warnings require explicit, non-ambiguous wording. Human-review
/// coverage is initially 13 languages; other locales fall back to English
/// without modifying the 64 frozen release localization catalogs.
enum ProxyShareUX {
    private static let fallback: [String: String] = [
        "Поделиться": "Share",
        "Поделиться данными прокси?": "Share proxy credentials?",
        "Показать QR-код": "Show QR code",
        "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "The QR code contains the proxy address, username and password. Share only with people you trust.",
        "Не удалось создать QR-код": "Could not create QR code",
        "Отправить QR-код": "Share QR code",
        "QR-код для импорта прокси": "QR code for importing a proxy",
    ]
    private static let translated: [String: [String: String]] = [
        "ru": [
            "Поделиться": "Поделиться",
            "Поделиться данными прокси?": "Поделиться данными прокси?",
            "Показать QR-код": "Показать QR-код",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.",
            "Не удалось создать QR-код": "Не удалось создать QR-код",
            "Отправить QR-код": "Отправить QR-код",
            "QR-код для импорта прокси": "QR-код для импорта прокси",
        ],
        "de": [
            "Поделиться": "Teilen",
            "Поделиться данными прокси?": "Proxy-Zugangsdaten teilen?",
            "Показать QR-код": "QR-Code anzeigen",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "Der QR-Code enthält Proxy-Adresse, Benutzername und Passwort. Nur mit vertrauenswürdigen Personen teilen.",
            "Не удалось создать QR-код": "QR-Code konnte nicht erstellt werden",
            "Отправить QR-код": "QR-Code teilen",
            "QR-код для импорта прокси": "QR-Code zum Importieren eines Proxys",
        ],
        "fr": [
            "Поделиться": "Partager",
            "Поделиться данными прокси?": "Partager les identifiants du proxy ?",
            "Показать QR-код": "Afficher le code QR",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "Le code QR contient l’adresse du proxy, le nom d’utilisateur et le mot de passe. Ne le partagez qu’avec des personnes de confiance.",
            "Не удалось создать QR-код": "Impossible de créer le code QR",
            "Отправить QR-код": "Partager le code QR",
            "QR-код для импорта прокси": "Code QR pour importer un proxy",
        ],
        "es": [
            "Поделиться": "Compartir",
            "Поделиться данными прокси?": "¿Compartir las credenciales del proxy?",
            "Показать QR-код": "Mostrar código QR",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "El código QR contiene la dirección del proxy, el usuario y la contraseña. Compártelo solo con personas de confianza.",
            "Не удалось создать QR-код": "No se pudo crear el código QR",
            "Отправить QR-код": "Compartir código QR",
            "QR-код для импорта прокси": "Código QR para importar un proxy",
        ],
        "it": [
            "Поделиться": "Condividi",
            "Поделиться данными прокси?": "Condividere le credenziali del proxy?",
            "Показать QR-код": "Mostra codice QR",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "Il codice QR contiene indirizzo, nome utente e password del proxy. Condividilo solo con persone fidate.",
            "Не удалось создать QR-код": "Impossibile creare il codice QR",
            "Отправить QR-код": "Condividi codice QR",
            "QR-код для импорта прокси": "Codice QR per importare un proxy",
        ],
        "pt": [
            "Поделиться": "Compartilhar",
            "Поделиться данными прокси?": "Compartilhar credenciais do proxy?",
            "Показать QR-код": "Mostrar código QR",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "O código QR contém o endereço, o usuário e a senha do proxy. Compartilhe apenas com pessoas de confiança.",
            "Не удалось создать QR-код": "Não foi possível criar o código QR",
            "Отправить QR-код": "Compartilhar código QR",
            "QR-код для импорта прокси": "Código QR para importar um proxy",
        ],
        "uk": [
            "Поделиться": "Поділитися",
            "Поделиться данными прокси?": "Поділитися даними доступу до проксі?",
            "Показать QR-код": "Показати QR-код",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "QR-код містить адресу проксі, ім’я користувача й пароль. Діліться лише з тими, кому довіряєте.",
            "Не удалось создать QR-код": "Не вдалося створити QR-код",
            "Отправить QR-код": "Надіслати QR-код",
            "QR-код для импорта прокси": "QR-код для імпорту проксі",
        ],
        "ja": [
            "Поделиться": "共有",
            "Поделиться данными прокси?": "プロキシの認証情報を共有しますか？",
            "Показать QR-код": "QRコードを表示",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "QRコードにはプロキシのアドレス、ユーザー名、パスワードが含まれます。信頼できる相手にのみ共有してください。",
            "Не удалось создать QR-код": "QRコードを作成できませんでした",
            "Отправить QR-код": "QRコードを共有",
            "QR-код для импорта прокси": "プロキシをインポートするQRコード",
        ],
        "ko": [
            "Поделиться": "공유",
            "Поделиться данными прокси?": "프록시 로그인 정보를 공유하시겠습니까?",
            "Показать QR-код": "QR 코드 표시",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "QR 코드에는 프록시 주소, 사용자 이름 및 비밀번호가 포함됩니다. 신뢰할 수 있는 사람에게만 공유하세요.",
            "Не удалось создать QR-код": "QR 코드를 만들 수 없습니다",
            "Отправить QR-код": "QR 코드 공유",
            "QR-код для импорта прокси": "프록시 가져오기용 QR 코드",
        ],
        "zh-Hans": [
            "Поделиться": "分享",
            "Поделиться данными прокси?": "分享代理凭据？",
            "Показать QR-код": "显示二维码",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "二维码包含代理地址、用户名和密码。请仅分享给可信任的人。",
            "Не удалось создать QR-код": "无法创建二维码",
            "Отправить QR-код": "分享二维码",
            "QR-код для импорта прокси": "用于导入代理的二维码",
        ],
        "zh-Hant": [
            "Поделиться": "分享",
            "Поделиться данными прокси?": "分享代理登入資訊？",
            "Показать QR-код": "顯示 QR 碼",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "QR 碼包含代理位址、使用者名稱和密碼。請僅分享給信任的人。",
            "Не удалось создать QR-код": "無法建立 QR 碼",
            "Отправить QR-код": "分享 QR 碼",
            "QR-код для импорта прокси": "用於匯入代理的 QR 碼",
        ],
        "tr": [
            "Поделиться": "Paylaş",
            "Поделиться данными прокси?": "Proxy giriş bilgileri paylaşılsın mı?",
            "Показать QR-код": "QR kodunu göster",
            "QR-код содержит адрес прокси, логин и пароль. Делитесь только с теми, кому доверяете.": "QR kodu proxy adresini, kullanıcı adını ve şifreyi içerir. Yalnızca güvendiğiniz kişilerle paylaşın.",
            "Не удалось создать QR-код": "QR kodu oluşturulamadı",
            "Отправить QR-код": "QR kodunu paylaş",
            "QR-код для импорта прокси": "Proxy içe aktarma QR kodu",
        ],
    ]
    static func text(_ key: String) -> String {
        let language = AppL10n.effectiveLanguage
        if language == "ru" { return key }
        let base = String(language.split(separator: "-").first ?? "")
        return translated[language]?[key] ?? translated[base]?[key] ?? fallback[key] ?? key
    }
}
