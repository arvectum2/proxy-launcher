# App Store metadata — Arvectum Proxy Launcher iOS 0.1.36

## App record
- Platform: iOS
- Name: Arvectum Proxy Launcher
- Primary language: Russian
- Bundle ID: ru.arvectum.proxylauncher.ios
- SKU: APL-IOS-001
- Version: 0.1.36
- Build: 38
- Primary category: Utilities
- Secondary category: Productivity
- Price: Free

## Localized metadata — Russian
**Subtitle:** Прокси одним нажатием

**Promotional text:** Подключайте собственные HTTP, HTTPS и SOCKS5 прокси, переключайте профили и автоматизируйте APL без регистрации и облачного аккаунта.

**Description:**
Arvectum Proxy Launcher — сетевая утилита для подключения iPhone через прокси, который вы выбираете сами.

Возможности:
• HTTP, HTTPS CONNECT и SOCKS5 прокси
• несколько профилей и автоматический выбор доступного
• основной и резервные профили с автоматическим переключением
• автоматический возврат на основной прокси
• исключения для сайтов, которые должны идти напрямую
• автоматизация включения и выключения APL для выбранных приложений через «Команды» iOS
• локальный журнал состояния подключения
• адаптивный интерфейс для разных размеров экрана
• учётные данные остаются на устройстве
• без регистрации, рекламы, аналитики и облачного backend

APL использует системный Network Extension iOS. Приложение не предоставляет и не продаёт прокси-серверы: пользователь добавляет собственные параметры подключения.

ООО «Арвектум» не собирает и не передаёт пользовательский интернет-трафик или данные прокси.

**Keywords:** proxy,http,socks5,network,privacy,utility,connect

**Support URL:** https://arvectum2.github.io/proxy-launcher/support.html
**Privacy Policy URL:** https://arvectum2.github.io/proxy-launcher/privacy.html
**Marketing URL:** https://github.com/arvectum2/proxy-launcher

**Copyright:** 2026 LLC ARVECTUM

## App Privacy
- Data collection: No, we do not collect data from this app.
- Tracking: No.
- Privacy Policy URL: https://arvectum2.github.io/proxy-launcher/privacy.html

## Review notes — public-safe template
Arvectum Proxy Launcher 0.1.36 (38) is a local network utility for users who already have access to a proxy endpoint, including developers, testers, network administrators, and individual users. It does not operate, sell, or bundle VPN/proxy endpoints.

The app uses Apple's Network Extension / NETunnelProviderManager APIs to create a packet tunnel and route device traffic to the proxy selected by the user. Users may configure HTTP, HTTPS CONNECT, or SOCKS5 proxy profiles. The app supports automatic profile selection/failover, optional return to the primary profile, site exclusions, and optional iOS Shortcuts automations that switch APL when a user-selected application is opened or closed.

No Arvectum account, registration, login, purchase, subscription, or sample file is required. Proxy configuration remains local to the device; proxy passwords are stored in the iOS Keychain. LLC ARVECTUM does not operate an intermediary server in this path.

This release has no Arvectum cloud backend, payment processor, AI service, advertising SDK, analytics SDK, or tracking service. GitHub Pages hosts only the public privacy-policy and support pages.

The feature set is the same in all selected App Store regions. Actual connectivity depends on the user's network and the reachability of the proxy endpoint they choose.

The app is not a finance, health, gambling, news, religious, book/magazine, or other regulated-industry service, and it contains no protected third-party media/content.

Testing:
1. Launch the app and accept the first-launch privacy disclosure if shown.
2. Add or select a valid HTTP/HTTPS CONNECT/SOCKS5 proxy profile.
3. Tap Connect and accept the standard iOS VPN configuration prompt if shown.
4. Confirm Connected status and use normal network traffic.
5. Optionally open Settings → Application automation to see the Shortcuts-based setup guidance.
6. Tap Disconnect.

No sign-in is required. Private temporary review-proxy credentials, when needed, must be added only to App Store Connect review notes/reply and must not be committed to the repository.

A physical-device screen recording on iPhone 13 running iOS 27 is attached to the App Review correspondence and demonstrates launch, the current 0.1.36 UI, proxy selection, connect/connected state, and disconnect.
