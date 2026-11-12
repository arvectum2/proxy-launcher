# APL iOS 0.3.0 — внешний HTTPS nonce и egress IP на iPhone

Дата: 12.11.2026, ~21:29 MSK. Физический iPhone13 / iOS27.2.1, подписанный Development Debug APL 0.3.0(49), сохранены 3 ранее настроенных прокси.

## Контролируемая методика

- Независимый аппаратный XCTest PhysicalHTTPSReceiptReadOnlyTests.testExistingProfilesProduceExternalHTTPSNonceWithoutSystemVPN запускается только из отдельной Xcode-схемы ArvectumKeychainReadOnlyQA, пропускается на симуляторе и никогда не входит в обычную UI/App Store схему.
- Тест внутри подписанного основного приложения читает существующие профили и пароли из ProfileStore/Keychain, использует оригинальный ProxyProbe для выбора реального HTTP(S) CONNECT/SOCKS5 транспорта.
- Для каждого профиля создаётся временная URLSessionConfiguration.ephemeral с Network.ProxyConfiguration, applyCredential и allowFailover=false. Не используется системный VPN или NEPacketTunnelProvider.
- Публичный HTTPS endpoint httpbingo.org/get получает одноразовый несекретный маркер в query и возвращает его в JSON args.qa_nonce с origin адресом внешнего клиента.
- Тест проверяет, что echo-маркер совпадает, status=200, и origin через прокси отличается от отдельного прямого iPhone baseline. Ни прямой IP, ни IP прокси, ни имя, адрес, UUID и Keychain пароль не попадают в журналы. Сеансы закрываются после запросов.
- Тест **не** подтверждает маршрутизацию системного VPN, DNS внутри PacketTunnel, IPv6/UDP, Wi-Fi/LTE и VLESS/standard WG/AmneziaWG.

## Результаты

- [x] Физический iPhone13: HTTPS nonce-confirmed ответ через прокси 1 — PASS; внешнее origin отличается от прямого.
- [x] Физический iPhone13: HTTPS nonce-confirmed ответ через прокси 2 — PASS; внешнее origin отличается от прямого.
- [x] Физический iPhone13: HTTPS nonce-confirmed ответ через прокси 3 — PASS; внешнее origin отличается от прямого.
- [x] 3/3 успешных подтверждённых HTTPS egress, XCTest PASS за 3.435 s. Встроенный обход напрямую запрещён allowFailover=false; отсутствие обхода подтверждено различием origin на успешных соединениях.
- [x] После теста CoreDevice повторно прочитал App Group preferences: profiles.v1 побайтно совпадает с оригиналом после установки, выбранный профиль тоже не изменился.
- [x] Симулятор: 1 skipped, 0 failed, TEST SUCCEEDED. Полный локальный набор Python318+1513 и Swift226 PASS.
- [ ] Оставшиеся отдельные этапы: проверка пакетов через реальный PacketTunnel, DNS/IPv4/IPv6/UDP, fail-closed, Wi-Fi/LTE, native VLESS/WireGuard и CloudKit; зашифрованный app-level .aplbackup пока отсутствует.

Приватный лог хранится на Mac mini: /tmp/apl030-physical-https-receipt-20261112.log. Только синтетические маркеры и безопасные PASS/FAIL-статусы, без адресов и паролей. Это функциональная QA-проверка существующих прокси, а не согласование публикации приложения.
