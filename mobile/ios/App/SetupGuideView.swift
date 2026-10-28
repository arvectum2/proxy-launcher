import SwiftUI

/// A short, skippable guide. APL does not sell or supply proxy credentials.
struct SetupGuideView: View {
    let onClose: () -> Void
    let onCreateProfile: () -> Void

    @State private var step = 0

    private struct GuideStep: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let explanation: String
        let detail: String
    }

    private let steps: [GuideStep] = [
        GuideStep(
            id: 0, symbol: "key.horizontal.fill",
            title: "Подготовьте данные прокси",
            explanation: "APL подключает ваш собственный прокси. Адрес, порт, тип и, при необходимости, логин с паролем вам сообщает поставщик прокси или администратор сети.",
            detail: "APL не продаёт и не предоставляет прокси-серверы. Без действующих данных подключиться не получится."
        ),
        GuideStep(
            id: 1, symbol: "rectangle.stack.badge.plus",
            title: "Создайте профиль",
            explanation: "Откройте «Профили» и нажмите «Добавить первый прокси» (или «Новый», если профили уже есть). Укажите адрес сервера, порт и тип (HTTP, HTTPS или SOCKS5). Логин и пароль нужны только при авторизации.",
            detail: "Если тип подключения неизвестен, уточните его у поставщика. После заполнения нажмите «Сохранить»."
        ),
        GuideStep(
            id: 2, symbol: "power.circle.fill",
            title: "Подключитесь",
            explanation: "На вкладке «Главная» выберите профиль и нажмите «Подключиться». При первом подключении iOS попросит разрешить VPN-конфигурацию — подтвердите системный запрос.",
            detail: "Следите за статусом соединения. Если подключение не удалось, проверьте адрес, порт, тип и учётные данные."
        )
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                HStack(spacing: 7) {
                    ForEach(steps) { item in
                        Capsule()
                            .fill(item.id == step ? Brand.mint : Brand.softGray.opacity(0.3))
                            .frame(height: 5)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .accessibilityLabel(AppL10n.tr("Шаг") + " \(step + 1) / \(steps.count)")

                TabView(selection: $step) {
                    ForEach(steps) { item in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 19) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 40, weight: .medium))
                                    .foregroundStyle(Brand.mint)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 30)

                                Text(AppL10n.tr(item.title))
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(Brand.text)

                                Text(AppL10n.tr(item.explanation))
                                    .font(.body)
                                    .foregroundStyle(Brand.text)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(AppL10n.tr(item.detail))
                                    .font(.subheadline)
                                    .foregroundStyle(Brand.softGray)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 25)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 10) {
                    Button {
                        if step < steps.count - 1 {
                            withAnimation { step += 1 }
                        } else {
                            onCreateProfile()
                        }
                    } label: {
                        Text(AppL10n.tr(step == steps.count - 1 ? "Создать профиль" : "Далее"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(Brand.actionText)
                            .background(Brand.mint, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button(AppL10n.tr("Закрыть инструкцию")) { onClose() }
                        .font(.subheadline)
                        .foregroundStyle(Brand.mintLight)
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle("Первое подключение")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
