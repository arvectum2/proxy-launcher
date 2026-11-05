# APL iOS — автономная офлайн-приёмка без телефона

Дата: 05.11.2026. Задача `APL-IOS-OFFLINE-SPRINT-20261105`. Исходная ветка `main`: `a0b4856e` после слияния исходной DEBUG native-flow трассировки.

## Область работ

Только исходный код, изолированный worktree, локальный loopback и disposable iOS Simulator. **Реальный iPhone, VPN-профили, Keychain, App Store Connect, iCloud entitlements, production DIRECT, черновик FIN PR #314 не затрагивались**. Рабочая директория канонического checkout оказалась грязной и расходящейся с `origin/main`; любые изменения выполнены в отдельном чистом worktree.

## Новые функции и исправления

1. `scripts/qa_smart4_offline_harness.py`: одна команда поднимает раздельные DIRECT и PROXY TCP witnesses плюс CONNECT-посредник, создаёт приватный одноразовый набор `0600`, отправляет по 128-битному токену каждому наблюдателю, ожидает положительные ACK, отвергает отсутствие/подмену, запускает существующий bounded verifier, завершает процессы и очищает временный каталог в `finally`. Лабораторное положительное свидетельство всегда имеет `scope=synthetic_loopback_only`, `original_packettunnel_flow_verified=false`, `physical_egress_verified=false`. Это **не** доказательство физического маршрута и не изменение tun2proxy.
2. `ProxyImport.parse`: исправлен импорт BOM-prefixed файлов, когда после UTF-8 BOM перед форматом содержатся переносы строк/пробелы; распознаются URL, JSON, XML и CSV; пустой BOM-файл по-прежнему отвергается. Ограничения 256 KB, 200 записей и отсутствие частичного импорта сохранены.
3. `ActivityScreenView`: кнопка обновления получила реальную область нажатия **48×48 pt на содержимом Button** (раньше внешний frame не влиял на accessibility hit area). Пустое состояние явно переводится существующим `AppL10n.tr` для 64 локалей. UI-тест на Accessibility XXL до проверки hit area прокручивает ScrollView, поскольку длинный статус на крупном шрифте закономерно может выходить за первую видимую область.

## Проведённые проверки

- Новые независимые Python harness tests: 7/7 PASS, включая два настоящих loopback TCP-наблюдателя, 0600 permissions, подмену токена, отказ DIRECT, безопасное очищение и non-POSIX отказ.
- Swift Core 195/195 PASS, включая новые BOM тесты для четырёх входных форматов.
- iOS Python **212 тестов (один skipped) PASS**; 64/64 каталога ресурсов и 320/320 `.strings` `plutil -lint` PASS, 0 missing/error в существующем структурном аудиторе.
- Первичная Simulator UI suite: 4/5 PASS (10 языков, импорт, fr/am заголовки, UX); единственный FAIL выявил область Activity Refresh ~39×20 pt. После исправления до 48×48 pt и проверки прокрутки при длинном статусе **реальный Accessibility XXL de/ar XCTest 1/1 PASS (34,095 с)**, категория Dynamic Type возвращена.
- Дополнительные Simulator dark appearance + Increase Contrast: компактные Settings **1/1 PASS (10,168 с)** и скрытие клавиатуры в пяти формах **1/1 PASS (42,059 с)**; appearance/contrast возвращены `light/disabled`.
- Unsigned iPhoneOS ARM64 **Debug и Release App + PacketTunnel BUILD PASS**; unsigned iOS Simulator ARM64 App+PacketTunnel BUILD PASS; Swift Core195/195 PASS. После изменения 48×48 обновлён старый source-контракт, ошибочно требовавший внешний frame ровно 44×44: полный итоговый Python212 (один skipped) PASS.
- Синтетический QR UI-test на unsigned simulator аварийно завершился в `AppViewModel.init` (`EXC_BREAKPOINT`) при создании фиктивной Keychain-записи. Этот тип теста требует подписанного Simulator с App Group/Keychain; **тот же QR sender/consent test 1/1 PASS (15,511 с)** при `CODE_SIGNING_ALLOWED=YES`, `codesign --verify --deep --strict=0`. Реального обмена секретами не было; это ограничение QA окружения, а не подтверждённый продуктовый краш.

## Что принципиально нельзя закрыть без телефона/внешних сервисов

- Smart4 аппаратный gate 2b.2: требуется **один и тот же original captured PacketTunnel flow**, решение для точного hostname и независимый DIRECT/PROXY серверный receipt; IPv6/UDP/QUIC, Wi-Fi/LTE, TTL/откат проверяются на настоящем устройстве. Текущий loopback всегда остаётся synthetic-only.
- Публичный upgrade App Store 0.1.41→0.2.0 с настоящим Keychain и двухустройственная передача QR — требуют устройств / QR-содержащей опубликованной версии.
- Фактическое одобрение 0.2.0 — внешний Apple gate; считывание статуса не равно публикации. Независимая лингвистическая проверка переводов носителями 64 языков не заменяется автоматическим аудитом.
- iCloud CloudKit entitlements, production DIRECT и PR #314 не должны включаться без отдельного продуктового/аппаратного решения.

## Воспроизведение

```sh
python3 scripts/qa_smart4_offline_harness.py
python3 -m unittest -q tests.test_ios_smart4_offline_harness tests.test_ios_activity_accessibility_source
python3 -m unittest discover -s tests -p 'test_ios_*.py' -q
swift test --package-path mobile/ios
python3 scripts/ios_020_locale_audit.py --json
find mobile/ios/Resources -type f -name '*.strings' -print0 | xargs -0 -n 1 plutil -lint
```

Все положительные результаты относятся к коду, лабораторному TCP или симулятору, а не к приложению, установленному у пользователя.
