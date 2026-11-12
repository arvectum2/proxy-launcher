# APL iOS 0.3.0 — физическая read-only проверка Keychain

Дата: 12.11.2026, ~19:57 MSK. После разрешённой владельцем установки Development Debug 0.3.0 (49) поверх 0.2.0 необходимо отдельно доказать сохранность паролей трёх существующих прокси.

## Метод

- Отдельный Xcodegen target PhysicalKeychainReadOnlyTests и схема ArvectumKeychainReadOnlyQA — не входят в обычную продуктовую схему.
- XCTest выполняется в процессе основного подписанного приложения с исходной группой Keychain.
- Тест получает ProfileStore.listProfiles() и для трёх профилей с аутентификацией вызывает исключительно ProfileStore.password(for:).
- Проверяется наличие трёх профилей, непустого username и непустого пароля для каждого. Пароли, адреса, имена и UUID не выводятся, не записываются, не копируются и не изменяются.
- На Simulator/CI XCTest пропускается через targetEnvironment(simulator) и XCTSkip. Схема запускается только явно.

## Результаты

- [x] Физический iPhone 13 / iOS 27.2.1: unit-test testThreeExistingAuthenticatedProfilesCanReadKeychainWithoutMutation PASS, 0.004 s; все 3/3 записей Keychain доступны.
- [x] Повторно прочитаны App Group preferences после XCTest: профили и выбранный ID совпадают побайтно со снимком сразу после установки.
- [x] Simulator: 1 skipped, 0 failed, TEST SUCCEEDED.
- [ ] Подключение к реальным HTTP/SOCKS5 прокси, DNS/IPv4/IPv6/UDP, Wi-Fi/LTE и отказоустойчивость не проверены.
- [ ] Внешний зашифрованный .aplbackup не создан; iCloud Backup и приватные метаданные на Mac mini не являются полным экспортом Keychain.
- [ ] Native VLESS/WireGuard, CloudKit entitlement и публичный App Store 0.3.0 не приняты.

Предупреждение StoreKit Sandbox о тестовом аккаунте не мешало тесту Keychain, завершившемуся PASS. VPN при проверке не включался.
