import SwiftUI

struct PrivacyDisclosureView: View {
    let onContinue: () -> Void

    private let privacyURL = URL(string: "https://arvectum2.github.io/proxy-launcher/privacy.html")!

    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.078, blue: 0.196)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image("ArvectumWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 34)
                        .padding(.top, 28)

                    Text("Конфиденциальность")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Перед первым подключением")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.43, green: 0.95, blue: 0.84))

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
                    .foregroundStyle(Color(red: 0.04, green: 0.79, blue: 0.67))

                    Button(action: onContinue) {
                        Text("Понятно, продолжить")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(Color(red: 0.0, green: 0.078, blue: 0.196))
                            .background(Color(red: 0.04, green: 0.79, blue: 0.67))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    Text("Продолжая, вы подтверждаете, что ознакомились с описанием обработки данных.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.58))
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
                .foregroundStyle(Color(red: 0.43, green: 0.95, blue: 0.84))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
