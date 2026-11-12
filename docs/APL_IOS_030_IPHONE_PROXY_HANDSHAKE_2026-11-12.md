# APL iOS 0.3.0 — физическая read-only проверка прокси, 12.11.2026

На физическом iPhone 13 / iOS 27.2.1 после согласованного обновления 0.2.0 до подписанной Debug 0.3.0(49) запущен изолированный тест с оригинальным ProxyProbe, ProfileStore и iOS Keychain внутри подписанного приложения.

## Границы проверки

- Тест PhysicalProxyHandshakeReadOnlyTests.testExistingProfilesCanNegotiateProxyTunnelWithoutEnablingVPN существует только в отдельной QA-схеме ArvectumKeychainReadOnlyQA и пропускается на CI-симуляторе.
- Тест пробует три ранее сохранённых прокси с их Keychain-паролями и вызывает production ProxyProbe.resolveMeasured: HTTP(S) CONNECT или SOCKS5 CONNECT к example.com:443.
- Тест не запускает NEPacketTunnelProvider, не меняет системные маршруты VPN, не создаёт и не удаляет профили и не пишет в Keychain.
- В журналах лишь анонимные индексы 1–3 и общий счётчик. IP, имена, UUID, логины и пароли не печатаются.

## Фактические результаты

- [x] На физическом iPhone/Xcode: 3/3 ранее сохранённых прокси успешно завершили авторизованное CONNECT/SOCKS5-согласование; XCTest PASS за 0.534 секунды.
- [x] После теста Xcode CoreDevice повторно скопировал App Group preferences в защищённый каталог Mac mini. Байты profiles.v1 и выбранный UUID идентичны исходному снимку сразу после установки.
- [x] Системный VPN не включался, профили и маршруты не изменялись.
- [x] Симулятор XCTest корректно пропущен: 1 skipped, 0 failed, TEST SUCCEEDED; полный прогон Python316+1513 и Swift226 PASS.
- [ ] Не проверены полный HTTPS-запрос и egress IP, пакетный TUN, DNS/IPv4/IPv6/UDP, Wi-Fi/LTE, VLESS/standard WireGuard/AmneziaWG.
- [ ] Нет отдельного полного зашифрованного .aplbackup, есть только более ранняя резервная копия iCloud Backup и приватный снимок метаданных.

Успешный CONNECT НЕ является доказательством полного HTTPS или VPN-трафика. Приватный лог находится на Mac mini: /tmp/apl030-physical-proxy-handshake-20261112.log.
