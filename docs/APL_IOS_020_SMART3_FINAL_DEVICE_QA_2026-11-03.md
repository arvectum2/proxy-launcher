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
- Локальный экспорт App Store Connect-format IPA: **EXPORT SUCCEEDED**, ZIP integrity PASS, файл 9 062 953 bytes; SHA-256: 3374d64ad490c75a1a4024c22696acb40d3eafa8e44bb2f33bcdda7e0ef1e472.
- Локальный IPA: /private/tmp/APL-iOS-020-Smart3-full-qa-20261103-export/Arvectum Proxy Launcher.ipa
- Локальный .xcarchive: /private/tmp/APL-iOS-020-Smart3-full-qa-20261103.xcarchive
- В архиве присутствуют Packet Tunnel и YandexMobileAds; исходники рекламы, конфигурация и privacy label не редактировались.

## Что нельзя объявлять проверенным

- Реальный радиопереход Wi-Fi→LTE→Wi-Fi **не проводился**, чтобы не менять связь и настройки владельца: на iPhone проверена именно функция revocation.
- Реальный physical IPv6-only scoped TCP до удалённого HTTPS хоста и разделение соседних доменов с общим IPv6 пока не подтверждены: Rust и Swift policy tests покрывают только модель и IPv6-only fallback.
- Для QUIC/DoH/ECH/raw-IP предусмотрено fail-closed по VirtualDNS exact-host и проксирование всех UDP/неатрибутированных потоков. Подтверждено кодом и тестами, но не полным adversarial-сетевым стендом на iPhone.
- Signed App Store archive не был установлен на персональный iPhone: профиль дистрибуции не допускает такую установку через devicectl, а DEBUG QA сценарии исключены из Release. Реальный Safari лабораторно проверен подписанной Development-сборкой с тем же tun2proxy и маршрутизацией.
- Apple App Review не запускался и допуск реализации **не подтверждён**. Владелец решил передать решение о допустимости Apple при подаче, без требования предварительного Apple DTS.

Не публиковать промежуточную урезанную реализацию. Перед upload нужны решения по оставшимся аппаратным сценариям, затем принятие полного RC и доступность номера сборки в App Store Connect.
