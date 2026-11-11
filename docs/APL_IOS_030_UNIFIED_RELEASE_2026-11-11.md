# APL iOS — единый крупный релиз 0.3.0 (план и критерии приёмки)

Дата решения: 11.11.2026. Владелец попросил не дробить новые iOS-возможности на цепочку мелких публичных версий. **Целевой номер следующего нового релиза — 0.3.0; это не опубликованная версия и номер ещё не меняется в Xcode.** Рабочая App Store версия 0.2.0 и её двоичные артефакты не трогать.

## Состав одного релиза и честные статусы

| Направление | Состояние исходников 11.11 | Что должно быть проверено до включения в подписанный IPA |
| --- | --- | --- |
| Универсальный импорт, QR/Share, JSON/XML/CSV/TXT | В main; ожидает публикации | Подписанная сборка, Keychain upgrade, QR/Share после первого QR-релиза по ранее согласованной политике |
| Безопасные ошибки DNS/TCP/HTTP 407/Keychain, исключения | В main; ожидает публикации | Регрессионные и релизные проверки без разглашения данных |
| Загрузка списка прокси поставщика по HTTPS (raw/Base64) | В main после PR #356 | Redirect/size/timeouts, Swift+ARM64, предпросмотр и ручное подтверждение; поддержка только реально работающих HTTP/HTTPS/SOCKS5 |
| Сохранённые подписки с ручным обновлением | **В main после PR #356:** URL/token в Keychain, список названий/доменов, ручная загрузка и удаление | Проверить Keychain на подписанном iPhone и отсутствие автоматической замены профилей; автоматическое фоновое обновление, разрешения и signed-provider trust остаются отдельно не реализованы |
| iCloud/CloudKit исключений | Snapshot/diff в main; отдельный **CloudKit private DB backend и UI готовы в source**, но экран скрыт `APL_CLOUDKIT_ENABLED`, entitlement отсутствует | Реальный private container, entitlement/provisioning, opt-in, conflict/merge, несколько устройств, privacy label |
| VLESS/Reality | Транспорт **НЕ реализован**; source-only строгая проверка REALITY/TCP ссылок и CGo API v3 contract, libXray v26.11.9 прошёл изолированный ARM64 Simulator conversion/start-stop/SOCKS-local receipt. [Исследование](APL_IOS_030_XRAY_RESEARCH_2026-11-11.md) | Выбор независимого iOS PacketTunnel transport, исходники/лицензия, пин версии и SBOM, IPv4/IPv6/DNS, egress/rollback, реальный сервер |
| WireGuard/AmneziaWG | **НЕ реализовано** | Совместимый iOS backend, ключи в Keychain, UDP/handshake/failover, независимый физический egress, лицензирование |
| Smart Routing 4.0 | DEBUG witness/TTL готовы; production DIRECT gate **открыт** | Связать original captured PacketTunnel flow с независимыми DIRECT/PROXY nonce, shared CDN IPv4/IPv6, QUIC, network revoke |
| Native FIN/CLOSE_WAIT PR #314 | Draft, запрещено включать без теста | Реальный iPhone FIN, длительные Safari upload/download, переключение Wi-Fi/LTE, отсутствие обрывов |

**Важное ограничение:** работающий парсер ссылки/конфига не равен рабочему VPN-протоколу. Непроверенные протоколы не добавлять в `ProxyType` и не отображать как доступные пользователю; экспериментальные Smart4/FIN не проталкивать в production.

## Архитектурные решения перед интеграцией

1. Существующий `tun2proxy` используется для HTTP/HTTPS/SOCKS5; новые протоколы требуют явного абстрактного адаптера транспорта и отдельного механизма запуска/отзыва NetworkExtension; не смешивать с раздельными системными PAC-обходами.
2. Провести отдельный юридический аудит GPLv3 выбранного движка sing-box перед включением в распространяемый коммерческий APL; официальные исходники https://github.com/SagerNet/sing-box-for-apple , https://github.com/SagerNet/sing-box . Доступная реализация Apple PacketTunnel/TUN не означает лицензионной совместимости или права копирования кода.
3. Для CloudKit не создавать iCloud-контейнер и не включать App ID capability автоматически до выбора реального контейнера и проверки Apple signing/permissions; см. https://developer.apple.com/documentation/xcode/configuring-icloud-services/ .
3a. Для VLESS/REALITY первым исследовать **Xray-core** под MPL-2.0 (https://github.com/XTLS/Xray-core) как более подходящий к коммерческому приложению кандидат, чем GPLv3 sing-box, но не включать библиотеку до проверки всей цепочки зависимостей и законной сборки iOS PacketTunnel. Для WireGuard первоначальный кандидат **WireGuardKit** (MIT, https://git.zx2c4.com/wireguard-apple/tree/COPYING); для AmneziaWG — отдельно проверить актуальный MIT fork (https://github.com/amnezia-vpn/amneziawg-apple/blob/master/COPYING) и совместимость конфигураций/версий. Лицензии компонентов не равны лицензиям всех транзитивных зависимостей.

4. Синхронизировать только вручную заданные исключения и метаданные по явному согласию. Никогда не реплицировать Keychain passwords, live Smart evidence, DNS/IP observations или Apple VPN preferences в обычном CloudKit payload.
5. При загрузке подписки по HTTPS не выполнять фоновые запросы или скрытые обновления; каждый импорт требует предварительного просмотра. Блокировать redirect, небезопасный host и превышение 256 КБ. Путь токена поставщика не записывать в журналы. Signed managed manifest — независимый trust contract, не смешивать с произвольным обычным URL.

## Критерии единой публикации

- [ ] Все заявленные в App Store функции реально работают в **одном конкретном** подписанном IPA и PacketTunnel; нерелизные протоколы не рекламируются как готовые.
- [ ] Непрерывное обновление с опубликованной версии: стабильные profile IDs, Keychain, выбор proxy, группы, исключения, `.aplbackup`.
- [ ] Реальное физическое egress на актуальном iPhone по каждому включаемому транспорту и при смене Wi-Fi/LTE.
- [ ] Регрессионные тесты Swift/iOS Python, Simulator/iPhoneOS Debug+Release, подписи/entitlements, конфиденциальность, 64 локали и App Store скриншоты.
- [ ] Release decision с фиксированным SHA/IPA и понятными фактическими статуса App Store Connect.
- [ ] Один реальный публичный выпуск `0.3.0` (или другой один номер, если Apple диктует номер); никаких промежуточных публичных версий только ради отдельных коммитов.

## Progress / 11.11

- [x] Отдельная ветка и canonical checkpoint.
- [x] Read-only инвентаризация: только `HTTP/HTTPS/SOCKS5` в `ProxyType`; `ManagedProfileContract` пока data-only; CloudKit entitlement отсутствует.
- [x] HTTPS subscription one-shot fetch + Base64/raw parser, безопасный preview и подтверждение импорта; 5 новых Swift unit tests PASS, unsigned ARM64 Simulator App+PacketTunnel BUILD PASS.
- [x] Data-only CloudKit manual-exclusions snapshot/diff, 4 новых Swift unit tests PASS; CloudKit network/entitlements НЕ включены.
- [x] Local-first сохранённые subscription sources: separate ThisDeviceOnly Keychain service, display metadata в App Group, повторная загрузка только вручную. Signed physical Keychain QA остаётся открытым.
- [x] Swift Core 206/206 PASS; iOS Python source contracts 288 PASS + 1513 subtests; unsigned ARM64 Simulator App+PacketTunnel BUILD PASS после внесения новых файлов.
- [x] PR #356 MERGED `f0349879`, exact-head GitHub CI 17/17 PASS, локальная main/GitHub/GitVerse совпали.
- [x] PR #357 MERGED `028081ed`, exact-head GitHub CI 17/17 PASS, CloudKit по-прежнему закрыт без Apple capability.
- [x] Stage 2 CloudKit private DB read/save: проверка Apple ID, лимиты/валидация, синхронизация **только** manual exclusions, CAS `.ifServerRecordUnchanged`, явно подтверждённые preview/apply/upload, откат VPN через обычный `saveExclusions`. UI не активирован без Apple entitlements.
- [x] Обнаружено и закрыто UX-риск: закрытие iCloud sheet не стирает несохранённые исключения; кнопка отключена при несохранённых изменениях.
- [x] CloudKit gated UI Simulator Debug BUILD PASS и обычная unsigned iPhoneOS Release BUILD PASS; Swift Core207 + iOS Python292 / 1513 subtests PASS, 4 новых iOS статических gate-теста.
- [x] libXray v26.11.9 Apple cgo с официальным SHA-256 проверен отдельно от репозитория; симулятор запустил C API v3, преобразовал VLESS/Reality, запустил и остановил локальный SOCKS, выдал синтетический HTTP receipt; в production PacketTunnel runtime не подключён.
- [x] `VLESSRealityShareLink`: fail-closed валидатор REALITY/TCP, исходный URL не логируется и не записывается, Xray native v3 request формируется только после проверки; текущие HTTP/SOCKS профили и `ProxyType` не изменены.
- [ ] Физическая CloudKit двухустройственная приёмка, entitlement и включение UI; безопасная интеграция Xray/WireGuard транспорта; iPhone Keychain upgrade и egress; один подписанный релиз после gates.
