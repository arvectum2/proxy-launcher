# APL iOS 0.2.0 (48) — release candidate notes

**Status:** source-only candidate. Signed simulator UI smoke and unsigned ARM64 Release builds have passed; not in TestFlight or App Store. Physical iPhone acceptance is pending.

## Что нового

- Массовый импорт прокси из TXT, CSV, XML и строк `IP:порт:логин:пароль`, поддержка HTTP/HTTPS/SOCKS5.
- Избранные серверы, собственные группы, поиск, массовое назначение и удаление профилей с подтверждением.
- Экономная диагностика: до трёх автоматических проверок, ручные партии до десяти, индикация доступности и задержки.
- Режим Auto учитывает свежие результаты задержки при выборе резервного сервера; добавлены ограничения числа попыток подключения и интервала повторных проверок.
- Улучшена безопасность хранения паролей в Keychain и поведение при ошибках сохранения.
- Основное подключение остаётся в приложении, рекламный баннер РСЯ сохранён. Виджет подключения не добавлялся.

## What's new (en)

- Bulk import from TXT, CSV, XML and `host:port:username:password` provider lists (HTTP/HTTPS/SOCKS5).
- Favorites, custom groups, search, bulk organization and confirmed deletion.
- Metered-aware connection diagnostics with bounded automatic/manual checks and latency display.
- Improved Auto backup ranking and bounded retries; stronger Keychain error handling.
- Connect/Disconnect stays in the app with its existing ad placement. No quick-connect widget.

## Release gates outstanding

- Real-device upgrade preserves 0.1.41 profiles, Keychain secrets, exclusions, Shortcuts and VPN settings.
- Real proxy reachability, Auto failover and paid-proxy traffic usage checks on physical iPhone.
- Actual Yandex Mobile Ads banner loading/impressions on physical device; appropriate App Store privacy review.
- TestFlight install/smoke and explicit decision before Apple App Review submission.

No App Store Connect metadata or submission is modified by this source-only preparation.
