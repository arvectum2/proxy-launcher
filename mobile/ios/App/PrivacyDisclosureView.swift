import SwiftUI

struct PrivacyDisclosureView: View {
    let onContinue: () -> Void

    private let privacyURL = URL(string: "https://arvectum2.github.io/proxy-launcher/privacy.html")!

    var body: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image("ArvectumWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 34)
                        .padding(8)
                        .background(Brand.logoBacking, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 28)

                    Text("Конфиденциальность")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Brand.text)

                    Text("Перед первым подключением")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Brand.mintLight)

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
                        title: "Без аналитики и рекламы",
                        text: "В этой версии нет рекламных SDK, аналитики, трекинга, регистрации или облачного backend."
                    )

                    Link(destination: privacyURL) {
                        Label("Политика конфиденциальности", systemImage: "doc.text")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Brand.mint)

                    Button(action: onContinue) {
                        Text("Понятно, продолжить")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(Brand.actionText)
                            .background(Brand.mint)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    Text("Продолжая, вы подтверждаете, что ознакомились с описанием обработки данных.")
                        .font(.footnote)
                        .foregroundStyle(Brand.softGray)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private func disclosureRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.mintLight)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(AppL10n.tr(title))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Brand.text)
                Text(AppL10n.tr(text))
                    .font(.system(size: 15))
                    .foregroundStyle(Brand.softGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
