import SwiftUI

struct PrivacyDisclosureView: View {
    @Binding var appLanguage: String
    var reviewOnly = false
    let onContinue: () -> Void

    private let privacyURL = URL(string: "https://arvectum2.github.io/proxy-launcher/privacy.html")!

    var body: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Brand.wordmark
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 34)
                        .padding(8)
                        .background(Brand.logoBacking, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 28)

                    if !reviewOnly {
                    Picker(selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    } label: { Text(tr("Язык приложения")) }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("privacy.language")
                    }

                    Text(tr("Конфиденциальность"))
                        .font(.largeTitle.bold())
                        .foregroundStyle(Brand.text)

                    if !reviewOnly { Text(tr("Перед первым подключением"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Brand.mintLight) }

                    disclosureRow(
                        icon: "hand.raised.fill",
                        title: "Мы не собираем ваш трафик",
                        text: "Arvectum Proxy Launcher не собирает, не анализирует, не продаёт и не передаёт третьим лицам историю сайтов, содержимое трафика или сведения о подключениях."
                    )

                    disclosureRow(
                        icon: "key.fill",
                        title: "Данные прокси остаются на устройстве",
                        text: "Адрес, порт и логин сохраняются локально. Пароль хранится в системной Связке ключей iOS. Arvectum не получает эти данные."
                    )

                    disclosureRow(
                        icon: "network",
                        title: "Используется системный VPN-механизм iOS",
                        text: "APL создаёт конфигурацию Network Extension, чтобы направлять трафик через прокси, который вы добавили сами. Arvectum не предоставляет и не выбирает прокси-сервер за вас."
                    )

                    disclosureRow(
                        icon: "chart.bar.xaxis",
                        title: "Реклама в приложении",
                        text: "В приложении показывается реклама РСЯ. SDK Яндекса может обрабатывать технические данные устройства для загрузки объявлений."
                    )

                    Text(verbatim: AppL10n.tr("sdkManifestDisclosure", table: "PrivacyDetails", language: appLanguage))
                        .font(.footnote)
                        .foregroundStyle(Brand.softGray)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: privacyURL) {
                        Label(tr("Политика конфиденциальности"), systemImage: "doc.text")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Brand.mint)

                    Button(action: onContinue) {
                        Text(tr(reviewOnly ? "Закрыть" : "Понятно, продолжить"))
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(Brand.actionText)
                            .background(Brand.mint)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(reviewOnly ? "privacy.closeReview" : "privacy.continue")
                    .padding(.top, 4)

                    if !reviewOnly { Text(tr("Продолжая, вы подтверждаете, что ознакомились с описанием обработки данных."))
                        .font(.footnote)
                        .foregroundStyle(Brand.softGray)
                        .padding(.bottom, 30) }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
            }
        }
    }

    private func tr(_ key: String) -> String { AppL10n.tr(key, language: appLanguage) }

    private func disclosureRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.mintLight)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(tr(title))
                    .font(.headline)
                    .foregroundStyle(Brand.text)
                Text(tr(text))
                    .font(.body)
                    .foregroundStyle(Brand.softGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
