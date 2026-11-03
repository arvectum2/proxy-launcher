# iOS 0.2.0 — Smart3 Simulator QA, 03.11.2026

**Итог этапа:** 9/9 UI-тестов PASS, все проверки модели маршрутизации PASS, Release ARM64 Simulator BUILD SUCCEEDED. Версия 0.2.0 не публиковалась и не отправлялась в Apple. Реклама и privacy-настройки не изменялись.

## Среда

- Mac mini, Xcode 27.1.
- Отдельный одноразовый iPhone 17 Pro Simulator, iOS 27.0, UUID 56EC2AD4-0772-420B-A85D-B6E7F1CB3437.
- Ветка feat/ios-020-smart3-exact-flow-direct-20261103, отдельная от production main.
- Перед тестом состояния по умолчанию Simulator полностью очищен. Реальные прокси и пользовательские данные iPhone не использовались.

## Проверки

| Набор | Факт | Покрытие |
|---|---|---|
| iPhone Simulator UI, первая сессия | **8/8 PASS, 0 skipped** | Автообнаружение связанных поддоменов, единая группа A/www.A, ручное расширение, предупреждения об ошибке прокси и отсутствие скрытого IP-wide обхода, EN, HE/RTL, доступность экрана |
| iPhone Simulator UI, чистая установка | **1/1 PASS, 0 skipped** | Автоматическое расширение исключений включено по умолчанию |
| Swift Core | **132/132 PASS** | AdaptiveRouteLearning, срок и отзыв правил, смена сети, SmartFlowRoutingPolicy, работа с группами |
| Rust tun2proxy | **12/12 PASS** | Привязка VirtualDNS к точному hostname, динамическое одобрение/отзыв, запрет raw-IP bypass |
| Python iOS | **153/153 PASS, плюс 73 subtests** | Контракты исходников, безопасность лабораторного DIRECT, локализации, UI |
| Xcode Release для iOS Simulator ARM64 | **BUILD SUCCEEDED** | Приложение и Packet Tunnel; подпись отключена |
| Source release preflight | **PASS** | 0.2.0 (48), без загрузки в App Store Connect |

Добавлен детерминированный Swift Core тест для двух разных hostname с одинаковым физическим CDN IP: www.apple.com разрешён DIRECT, а www.apple.com.cn и другой соседний hostname остаются PROXY. При неизвестном hostname и прямом IP результат тоже PROXY. Проверены IPv4 23.12.156.37 и тестовый IPv6 2001:db8::37. **Это доказательство правил маршрутизации, не физической изоляции на общем IP.**

## Локальные результаты

- Основной XCTest: /private/tmp/apl-smart3-simulator-020-20261103.xcresult
- После сброса Simulator: /private/tmp/apl-smart3-simulator-fresh-default-20261103.xcresult
- Swift Core: /private/tmp/apl-smart3-sim-policy-shared-cdn-20261103.log
- Rust: /private/tmp/apl-smart3-policy-rust-20261103.log
- Python: /private/tmp/apl-smart3-policy-pytest-20261103.log
- ARM64 Release: /private/tmp/apl-smart3-sim-release-arm64-20261103.log

Первый вспомогательный generic Simulator Release build потребовал x86_64 и не слинковался с поставляемой только для arm64-simulator Rust-библиотекой. При явном выборе ARM64 симулятора Release успешно собрался. Это не ошибка ARM64 Release, но набор XCFramework не включает отдельный x86_64-simulator срез.

## Ограничения и решение владельца

На этом этапе не трогали физический iPhone. Ранее отдельно пройден реальный Safari A→B с автоматическим восстановлением исходного TCP/TLS, однако **симуляторные тесты сами по себе не проверяют настоящий physical DIRECT**. Они не заменяют испытаний изоляции двух разных сайтов на одном CDN IPv4/IPv6, смены Wi-Fi/LTE, QUIC/DoH/ECH и отката после ошибки.

Лабораторный exact-host DIRECT пока работает за явным DEBUG-флагом; в Release транспорт не активирован. Поэтому функция **ещё не готова к публичной публикации**, несмотря на успешный Simulator QA.

Решение владельца: допустимость архитектуры для App Store пусть оценивает **Apple App Review при реальной подаче**; предварительный Apple DTS не является обязательным продуктовым gate. Это не отменяет полного технического тестирования. Никакого промежуточного релиза; рекламу и принятую карточку конфиденциальности не менять.
