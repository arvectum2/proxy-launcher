# APL iOS 0.3.0 — граница автономной подготовки и приёмки на iPhone

Дата: 12.11.2026. Требование владельца: **сделать всё возможное без iPhone; аппаратную приёмку выполнить позже при доступности телефона**. Никаких изменений, установок, подписей, VPN-переключений или Apple App Store upload на iPhone в ходе offline-этапа не выполнять.

## Сделано и доказано без iPhone

- [x] Исходниковые QR/Share, универсальный импорт, безопасные ошибки, подписки с Keychain-ссылками и ручной загрузкой, CloudKit private-DB layer с выключенным entitlement, строгий неактивный VLESS/Reality и WireGuard/AmneziaWG1 preview — в `main`.
- [x] В отдельном native lab официальный pinned `libXray v26.11.9` связывается с существующим Rust `tun2proxy` в обоих PacketTunnel-бинарниках: iOS Simulator Debug arm64 и iPhoneOS Debug arm64, только **unsigned**.
- [x] На настоящем ARM64 iOS Simulator выполняется **сам Swift XrayNativeLabBridge**: версия 26.11.9 и семь полных последовательных/конкурентно инициированных `testXray → runXray → running → stopXray → stopped` циклов, изолированных одним `NSLock`. Исходящий маршрут `blackhole`, локальный SOCKS `127.0.0.1:39879`; нет внешнего трафика.
- [x] Data-only `XraySocksHandoffPlan`: точные `socks5://127.0.0.1:port`, TUN fd, virtual DNS, IPv6 и проверяемые DNS-bypass flags; не принимает строки, способные инъецировать CLI. **Не подключён** к production `PacketTunnelProvider`.
- [x] Data-only `XrayHandoffLifecycle`: обязательные этапы starting/running/stopping/drained, generation token, запрет повторного запуска после аварии, защита от запоздалого ошибки/callback.
- [x] Ни новый `ProxyType`, ни native Xray в production IPA, ни Apple iCloud entitlement не добавлены.

## Приёмка, когда будет доступен безопасный тестовый iPhone

| Проверка | Доказательство для PASS | Статус |
| --- | --- | --- |
| 0. Профили и миграция с опубликованной 0.2.0(48) | Бэкап, количество/ID профилей и исключений до и после, Keychain без потерь, rollback | NOT RUN — iPhone |
| 1. Подписки/QR/Share/локализации | Импорт после preview, URL-токен остаётся в Keychain, QR device-to-device, язык/VoiceOver | NOT RUN — iPhone |
| 2. Нативный Xray launch/stop | Подписанный **отдельный** QA-кандидат, DEBUG-only профили, Crash/Watchdog=0, гарантированный stop | NOT RUN — iPhone |
| 3. VLESS/Reality egress | Независимый nonce server подтверждает внешний IP, destination, session nonce; нет DNS leak/loopback recursion | NOT RUN — iPhone/сервер |
| 4. WireGuard egress | Проверенный настоящий server handshake + nonce, UDP/keepalive, IPv4/IPv6, DNS и MTU; не равен синтетическому config test | NOT RUN — iPhone/сервер |
| 5. Smart3 + Smart4 gate | Визуально и по внешним receipts подтверждены DNS-блокировки, исключения и отсутствие незапрошенного DIRECT | NOT RUN — iPhone |
| 6. Смена Wi-Fi/мобильная сеть | Переключение, отмена, повторное соединение и отсутствие fail-open, утечек и зависших сокетов | NOT RUN — iPhone |
| 7. CloudKit private user database | Только после App ID/entitlements: два разрешённых устройства, опциональный opt-in, конфликт и ручное применение | NOT RUN — два устройства |
| 8. Релиз 0.3.0 | Signed IPA exact SHA, entitlements/privacy/localizations, TestFlight/Review metadata, однократная публикация | NOT RUN — выпуск закрыт |

Обязательные ограничения: **тестировать на отдельном iPhone/тестовом профиле**, без потери действующего рабочего VPN. Включать новые протоколы лишь после реальных внешних receipt и оценки лицензий/транзитивных зависимостей. AmneziaWG не приравнивать к стандартному WG. Непроверенный Smart4 production DIRECT и native FIN PR #314 не включать.

## Следующий автономный инженерный этап

1. Продолжить **исключительно lab**: добавить безопасный ограниченный запуск `tun2proxy → localhost Xray SOCKS` в DEBUG NetworkExtension с явным fail-closed и stop-drain, без автоматического включения; все исходники, сценарии и сборки доступны без физического телефона.
2. Зафиксировать source + dependencies SHA, SBOM/licenses, проверить размер и ограничения памяти App Extension.
3. Провести симуляторные unit/UI/fault-injection сценарии профилей/исключений, затем выпустить **один** тестовый кандидат `0.3.0` после аппаратных ворот; не создавать промежуточные публичные 0.2.x.


## Зафиксированная граница offline QA / 12.11.2026

- [x] Исходниковые гейты объединены в canonical main через PR #361, SHA `0afa59fcb369bc40dcfd2e4f6af53ce61f4f3f26`, exact-head CI 17/17 PASS. GitHub/GitVerse/Mac mini совпадают.
- [x] Real iOS Simulator UI smoke `ProxyImportUITests.testImportPreviewForValidLink`: PASS на синтетическом `.invalid` домене, без запуска VPN.
- [x] Изолированная лабораторная ветка `research/ios-030-xray-native-link-20261112` SHA `d0e17ad8d5f627c99f4dc5132de48bdcac41240c`: `XrayDebugTunRunner` с локальным `blackhole` Xray SOCKS, Rust `tun2proxy`, строгим планом и serial `stopAndDrain`. DEBUG arm64 Simulator и iPhoneOS App+PacketTunnel BUILDS PASS; физический TUN runtime **NOT RUN**.
- [x] Swift CGo persistent Xray SOCKS running in Simulator: 4 независимых start/stop цикла PASS, повторный старт отвергнут, повторный stop идемпотентен.
- [x] Восстановление R&D: `/Users/master/ArvectumSafe/backups/proxy-launcher/apl-ios-030-xray-lab-20261112.bundle`, SHA-256 `17a6cfe56314b2cf475943210c0d0bc2bab0de66b6d5f40025781af516b1cb1b`. Native Apple CGO archive в отдельном R&D-кэше, **не в Git/IPA**.
- [ ] Возврат владельца с подключённым безопасным iPhone: начать физическую приёмку по таблице выше, до этого Xray/AWG/WG не включать в production.
