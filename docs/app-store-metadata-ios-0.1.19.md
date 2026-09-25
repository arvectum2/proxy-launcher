# App Store metadata — Arvectum Proxy Launcher iOS 0.1.19

## App record
- Platform: iOS
- Name: Arvectum Proxy Launcher
- Primary language: Russian
- Bundle ID: ru.arvectum.proxylauncher.ios
- SKU: APL-IOS-001
- Version: 0.1.19
- Build: 21
- Primary category: Utilities
- Secondary category: Productivity
- Price: Free

## Localized metadata — Russian
**Subtitle:** Прокси одним нажатием

**Promotional text:** Локальное подключение к вашим HTTP, HTTPS и SOCKS5 прокси без регистрации и облачного аккаунта.

**Description:**
Arvectum Proxy Launcher — простая сетевая утилита для подключения iPhone через прокси, который вы выбираете сами.

Возможности:
• HTTP, HTTPS CONNECT и SOCKS5 прокси
• автоматический выбор доступного прокси
• основной и резервные профили с автоматическим переключением
• автоматический возврат на основной прокси
• исключения для сайтов, которые должны идти напрямую
• локальный журнал событий подключения
• учётные данные хранятся на устройстве
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

## Review notes — English
Arvectum Proxy Launcher is a local network utility and does not operate, sell, or provide VPN/proxy endpoints. Users enter their own HTTP, HTTPS CONNECT, or SOCKS5 proxy settings.

The app uses Apple's Network Extension / NEVPNManager APIs to create a packet tunnel and route device traffic to the proxy selected by the user. LLC ARVECTUM does not operate an intermediary server in this path.

The app does not collect, sell, use, or disclose user traffic, browsing history, proxy credentials, device identifiers, analytics data, or advertising data. Proxy configuration is stored locally; proxy passwords are stored in the iOS Keychain. There are no ads, analytics SDKs, accounts, or an Arvectum cloud backend in this release.

On first launch, before the user can use the service, the app displays an in-app privacy disclosure describing these practices.

Testing:
1. Accept the first-launch privacy disclosure.
2. Add an HTTP/HTTPS CONNECT or SOCKS5 proxy profile that is accessible from the review device.
3. Select the profile and tap Connect.
4. iOS will ask to add/enable the VPN configuration on first use.
5. Once connected, normal device traffic is routed through the user-supplied proxy.

No sign-in or Arvectum account is required.
