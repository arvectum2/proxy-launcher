# APL iOS 0.2.0 Smart3 — аппаратные проверки и локальный подписанный RC

Дата: 03.11.2026. Ветка feat/ios-020-smart3-exact-flow-direct-20261103.
**Ни App Store Connect upload, ни merge, ни публикации не выполнялись.**

## Проверено на настоящем iPhone 13, iOS 27.2

Ранее на этой ветке пройдены: оригинальный Safari A→B HTTP 302 на HTTPS с двумя прокси-ошибками, двумя независимыми TLS-пробами, восстановлением исходного Safari TCP и отображением страницы без перезагрузки; а также A/B для двух разных CDN-hostnames с общим IPv4 23.12.156.37, где соседний hostname сохранил proxy CONNECT. Результаты приведены в APL_IOS_020_SMART3_EXACT_FLOW_DIRECT_LAB_2026-11-03.md.

В финальном сеансе добавлены два независимых теста отката реального Packet Tunnel, без изменения радионастроек владельца:

| Физический тест | Реальный результат |
| --- | --- |
| Смоделированное изменение сети (вызов той же функции отзыва, что и NWPathMonitor) | XCTest PASS, 1/1. После восстановления двух исходных TLS-потоков разрешение DIRECT отозвано. Следующее соединение пришло в mock upstream proxy; прямых TLS-ответов после отзыва нет. |
| Истечение срока разрешения (только QA TTL 4 секунды) | XCTest PASS, 1/1. После 2 TLS-ответов правило истекло, следующее соединение пошло в proxy, прямых ответов после истечения не было. |

Независимый анализ входов: scripts/qa_smart3_physical_evidence.py, режимы path и ttl, для **каждого**:
- original_tls_responses=2
- post_revoke_proxy_target_connects=1
- post_revoke_direct_tls_responses=0
- route_revocations=1

Фактические результаты:
- /private/tmp/apl-smart3-final-path-20261103.xcresult
- /private/tmp/apl-smart3-final-ttl-20261103.xcresult
- /private/tmp/apl-smart3-final-path-mock-20261103.log
- /private/tmp/apl-smart3-final-ttl-mock-20261103.log

После каждого теста App Group preferences (11 ключей) и app preferences (20 ключей) восстановлены из исходной копии; повторная выгрузка и per-value SHA-256 подтвердили **31/31 совпадений**. Реальные платные прокси и пользовательские VPN-сессии не изменялись; mock proxy никогда не пересылал CONNECT наружу.

## Проверка исходников и Release

- Rust tun2proxy v0.8.3, pinned source patches: 13/13 unit tests PASS, реальная static library aarch64-apple-ios собрана. SHA-256 исходного результата Cargo **совпадает с используемой в Xcode XCFramework библиотекой**: 2b9a73313812f9c5a6194c02ffc71a6b1dcda92a7c0e03d109f6c212ace556c7.
- Swift Core: 132/132 PASS.
- Python iOS source contracts: 156/156 PASS, дополнительно 73 subtests.
- Signed iPhone Debug build-for-testing: BUILD SUCCEEDED.
- Unsigned Release iPhoneOS: BUILD SUCCEEDED.
- Apple Distribution Release archive: **ARCHIVE SUCCEEDED**, bundle 0.2.0 (48), Team VML75VY94V, deep code-sign verification PASS включая Packet Tunnel.
- **Актуальный безопасный** App Store Connect-format IPA: **EXPORT SUCCEEDED**, ZIP integrity PASS, 9 056 686 bytes; SHA-256: 13df688a6865520cb1d6c321a56c4f2d94fd687c92005c1e0329e3f137ba0890.
- Актуальный IPA: /private/tmp/APL-iOS-020-Smart3-IPv6Safe-20261103-export/Arvectum Proxy Launcher.ipa
- Актуальный .xcarchive: /private/tmp/APL-iOS-020-Smart3-IPv6Safe-20261103.xcarchive
- Предшествующие архив/IPA без защиты IPv6-only от 20:52 **устарели и не должны использоваться для публикации**.
- В архиве присутствуют Packet Tunnel и YandexMobileAds; исходники рекламы, конфигурация и privacy label не редактировались.

## Дополнительный реальный IPv6 и проверка отсутствия регрессии IPv4, 21:00–21:08 МСК

- IPv6-only ipv6.google.com и его каноническое имя ipv6.l.google.com дают один набор IPv6 AAAA. Первый аппаратный тест выявил FAILED: оригинальные captured TLS не получили ответов, хотя IPv6 bound TCP фиксировался в telemetry. Отдельный hostname остался PROXY. Этот провал зафиксирован как дефект, а не принят за PASS.
- Source-pinned Rust patch теперь требует physical_direct_eligible(addr) = addr.is_ipv4() && public(addr.ip()). Для IPv6-only нет физического DIRECT-сокета; после попытки несовместимого маршрута разрешение отзывается. Rust cargo test: 13/13 PASS, воспроизведение pinned patch точь-в-точь PASS.
- **Повторный IPv6-only тест PASS**: XCTest testIPv6OnlyFailsClosedWithCanonicalNeighborProxy на iPhone13; независимый parser зафиксировал 7 upstream target CONNECT, 1 proxy CONNECT соседнего canonical host, **0 физических DIRECT IPv6-сокетов**, 0 DIRECT TLS-ответов, 2 автоматически отозванных неподтверждённых правила. Результат: /private/tmp/apl-smart3-ipv6-failclosed-device-20261103.xcresult.
- После исправления **повторно на iPhone PASS** shared-CDN IPv4 A/B: testSharedCDNHostIsNotBypassedByAHostRule. Независимый mock + App Group parser: 2 target proxy errors, 1 neighbor proxy accepted, 2 исходных TLS-потока восстановились, 1 fresh TLS получил байты, 3 физических DIRECT IPv4, **0 IPv6 DIRECT**. Результат: /private/tmp/apl-smart3-ipv4-regression-device-20261103.xcresult.
- После каждой из двух последних аппаратных проверок снова точно восстановлены 11 App Group + 20 app preference values, все per-value SHA256 совпали с pretest.

Актуальная Rust-библиотека из Cargo и Xcode XCFramework совпадают по SHA-256: a77224c970dfc9b8de853ebb7aeaebb7c0f21dba60647bd43def6e836c1baca8.

Контрактные тесты: **Python iOS 159/159 + 73 subtests**, Rust 13/13, Swift Core 132/132.

## Что нельзя объявлять проверенным

- Реальный радиопереход Wi-Fi→LTE→Wi-Fi **не проводился**, чтобы не менять связь и настройки владельца: на iPhone проверена именно функция revocation.
- На iPhone обнаружен дефект IPv6-only: прямой bound IPv6 TCP устанавливался, но ответ TLS не возвращался. Исправление: **запрет DIRECT для адресов без валидированного публичного IPv4**, fail-closed в прокси (или завершение исходного соединения при отказе upstream). Повторный физический тест IPv6-only PASS именно на запрет неиспытанного DIRECT; успешный IPv6 DIRECT по-прежнему **не реализован**.
- Для QUIC/DoH/ECH/raw-IP предусмотрено fail-closed по VirtualDNS exact-host и проксирование всех UDP/неатрибутированных потоков. Подтверждено кодом и тестами, но не полным adversarial-сетевым стендом на iPhone.
- Signed App Store archive не был установлен на персональный iPhone: профиль дистрибуции не допускает такую установку через devicectl, а DEBUG QA сценарии исключены из Release. Реальный Safari лабораторно проверен подписанной Development-сборкой с тем же tun2proxy и маршрутизацией.
- Apple App Review не запускался и допуск реализации **не подтверждён**. Владелец решил передать решение о допустимости Apple при подаче, без требования предварительного Apple DTS.

Не публиковать промежуточную урезанную реализацию. Перед upload нужны решения по оставшимся аппаратным сценариям, затем принятие полного RC и доступность номера сборки в App Store Connect.
