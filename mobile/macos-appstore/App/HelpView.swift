import SwiftUI

struct APLHelpView: View {
    let onClose: () -> Void

    private let repositoryURL = URL(string: "https://github.com/arvectum2/proxy-launcher")!
    private let releaseNotesURL = URL(string: "https://github.com/arvectum2/proxy-launcher/releases/latest")!
    private let reportProblemURL = URL(string: "https://github.com/arvectum2/proxy-launcher/issues/new")!
    private let privacyURL = URL(string: "https://arvectum2.github.io/proxy-launcher/privacy.html")!

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    helpHeader
                    gettingStarted
                    statusMeanings
                    proxyFormats
                    troubleshooting
                    aboutPrivacy
                    footer
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("Справка")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово", action: onClose)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 620)
    }

    private var helpHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Arvectum Proxy Launcher")
                .font(.title2.bold())
            Text("Офлайн-справка для версии Mac App Store")
                .foregroundStyle(.secondary)
        }
    }

    private var gettingStarted: some View {
        section("Начало работы") {
            Text("1. Нажмите «＋ Новый» и добавьте адрес, порт и при необходимости логин/пароль прокси.")
            Text("2. Выберите HTTP/HTTPS CONNECT/SOCKS5 или «Авто», затем сохраните профиль.")
            Text("3. Выберите профиль либо режим «Авто» и нажмите «Подключиться». macOS может попросить разрешить VPN-конфигурацию Arvectum.")
            Text("4. Для остановки нажмите «Отключить».")
        }
    }

    private var statusMeanings: some View {
        section("Статусы") {
            Text("Отключено / STOPPED — трафик через Arvectum не маршрутизируется.")
            Text("Подключение… — macOS запускает Packet Tunnel и применяет маршруты.")
            Text("Подключено / RUNNING — Packet Tunnel активен; выбранный прокси используется приложением.")
            Text("Переподключение… — Arvectum восстанавливает активное соединение или переключает прокси.")
            Text("System Proxy Enabled — статус прямой DMG-версии APL. Версия Mac App Store работает через Network Extension Packet Tunnel и не изменяет системный прокси через networksetup.")
        }
    }

    private var proxyFormats: some View {
        section("Форматы прокси") {
            Text("HTTP / HTTPS CONNECT: host:port, опционально username + password.")
            Text("HTTPS-proxy (TLS): соединение с upstream-прокси защищается TLS, затем используется CONNECT.")
            Text("SOCKS5: host:port, опционально username + password.")
            Text("Авто: APL проверяет сохранённые профили и выбирает доступный. Пароли хранятся локально в Keychain.")
        }
    }

    private var troubleshooting: some View {
        section("Устранение неполадок") {
            Text("Нет интернета: отключите APL, проверьте доступность выбранного прокси и повторите подключение.")
            Text("Safari или отдельные сайты недоступны: проверьте тип прокси и «Исключения». Для проблемного домена можно временно добавить исключение и проверить результат.")
            Text("После сна/пробуждения: дождитесь переподключения. Если статус не восстанавливается, отключите и снова включите APL.")
            Text("VPN-конфигурация зависла: отключите APL. При необходимости откройте Системные настройки → VPN и отключите Arvectum Proxy Launcher, затем запустите приложение снова.")
            Text("Версия Mac App Store не изменяет настройки networksetup, поэтому восстановление системного HTTP/HTTPS-прокси для неё не требуется.")
        }
    }

    private var aboutPrivacy: some View {
        section("О приложении и конфиденциальность") {
            Text("APL направляет сетевой трафик через выбранный вами прокси. Профили и учётные данные остаются на устройстве; пароль хранится в Keychain.")
            Text("APL не собирает, не продаёт и не передаёт историю посещений или содержимое пользовательского трафика. В этой версии нет рекламы и аналитики.")
            Text("Обновления версии Mac App Store доставляются через App Store. Встроенного self-updater, обходящего App Store, в этой сборке нет.")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Версия \(AppShared.version) · © Arvectum LLC")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 18) {
                Link("View on GitHub", destination: repositoryURL)
                Link("Release Notes", destination: releaseNotesURL)
                Link("Report a Problem", destination: reportProblemURL)
            }
            .font(.callout)
            Link("Политика конфиденциальности", destination: privacyURL)
                .font(.callout)
            Text("Проверка обновлений: откройте Mac App Store → Updates. Эта сборка намеренно не использует отдельный механизм обновления.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
