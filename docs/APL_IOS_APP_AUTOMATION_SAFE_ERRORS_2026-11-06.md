# iOS Shortcuts / автоматизация приложений: безопасная диагностика

Дата: 06.11.2026. Задача: `APL-IOS-APP-AUTOMATION-SAFE-ERRORS-20261106`.

## Обнаруженный риск

В `ApplicationExclusionsView.swift` четыре catch-обработчика (по два для загрузки/сохранения режима и применения baseline через системный VPN) напрямую показывали `error.localizedDescription`. Текст исключений `ProfileStore`, `NetworkExtension` и вложенных `NSError` не является проверенным: может включать внутренние пути, host, пользовательские реквизиты, адреса или сообщения провайдера.

## Исправление

- Чистый `SharedCore/AppAutomationFailureUX.swift` принимает только предустановленные переведённые сообщения `Сохранить`, `Настройки`, `Недоступен` и конечный диагностический код `STORE` либо классификацию `ProxyFailureReason`. Для неизвестных исключений VPN применяется безопасный фиксированный `VPN`.
- Все четыре обработчика экрана автоматизации используют этот formatter. Не передают в пользовательские сообщения `localizedDescription`, domain, userInfo, сетевой URL, путь или имя прокси.
- Все три ключа проверены в **64/64** существующих `Localizable.strings`. Новые непроверенные переводы не добавляются.
- `AppRoutingVPNControl`, Shortcuts AppIntents, `VPNController`, сохранение режима, права NetworkExtension, iCloud, production DIRECT и реальный VPN-профиль не изменялись. Локальный iPhone не использовался.

## Тесты и гейты

- 4 Swift unit tests: известные DNS/offline/timeout/TCP коды, анонимный NSError с userInfo и filepath, вложенный NSError и фиксированные переведённые строки. Всё без вывода секретов.
- 4 Python source-contract tests: все четыре catch-пути, отсутствие сырой диагностики, отсутствие VPN-команд в новом formatter и 64 каталога переводов.
- Полный Swift **201/201 PASS**; iOS Python **216 тестов, 1 skipped, 0 failures**. unsigned ARM64 iPhoneOS **Debug и Release** App+PacketTunnel и iOS Simulator App+PacketTunnel: **3/3 BUILD PASS**. Два локальных артефакта `tun2proxy.xcframework` (device/simulator) проверены по SHA256 относительно проверенного локального build-cache.
- Двухустройственное QR, фактический Keychain upgrade и независимый Smart4 hardware egress остаются отдельными неисполненными аппаратными gate; это не iPhone/Apple release update.
