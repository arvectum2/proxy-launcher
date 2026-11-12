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
| WireGuard/AmneziaWG | **Не работающий транспорт:** готов только fail-closed wg-quick/AmneziaWG1 предпросмотр (ключи не сохраняет), без UI и VPN-бэкенда; [гейты](APL_IOS_030_WIREGUARD_RESEARCH_2026-11-12.md) | Совместимый iOS backend, ключи в Keychain, UDP/handshake/failover, независимый физический egress, лицензирование |
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

## Progress / 12.11

- [x] PR #358 VLESS/REALITY source-only валидатор: exact-head GitHub CI 17/17, MERGED в `main` (`4640348f`), локальный Mac mini / GitHub / GitVerse в одинаковом SHA.
- [x] WireGuard / AmneziaWG1: безопасная синтаксическая проверка `.conf`, без загрузки секретов в хранилище, без добавления продукционного `ProxyType` или PacketTunnel engine. 7/7 Swift parser тестов и 3/3 source gates пройдены.
- [x] Ветка WireGuard: full Swift 220/220 PASS, Python 298 + 1513 subtests PASS; iOS Simulator Debug и iPhoneOS Release unsigned ARM64 App+PacketTunnel BUILD PASS.
- [x] PR #359 `ce211faa` MERGED exact-head 17/17 CI, репозитории Mac mini / GitHub / GitVerse совпали.
- [x] Проверена [техническая гипотеза единого Xray-бэкенда](APL_IOS_030_UNIFIED_XRAY_WG_ENGINE_2026-11-12.md): нативное совместное Rust+libXray линкование App+PacketTunnel unsigned Simulator/iPhoneOS ARM64 PASS; built-in стандартный WG outbound в libXray Simulator synthetic config/start/stop PASS.
- [ ] Предстоит настоящая реализация Xray/VLESS/REALITY и WireGuard/AmneziaWG native, внешний PacketTunnel egress и iCloud entitlements/физические тесты. AmneziaWG требует отдельной проверки. Одна публикация 0.3.0 после всех гейтов.

## Без iPhone — автономный этап 12.11.2026

- [x] [Контракт безопасного локального туннельного handoff](APL_IOS_030_DEVICE_ACCEPTANCE_HANDOFF_2026-11-12.md): strict `tunFD`/SOCKS port/DNS-bypass validation, deterministic `tun2proxy` CLI without proxy secrets, no production routing enablement.
- [x] Гейты жизненного цикла Xray: generation tokens, stale callback rejection, idempotent stop-drain, no automatic start after fail-closed, late failure after drain does not spoil next session.
- [x] [Offline native provenance gate](APL_IOS_030_XRAY_NATIVE_PROVENANCE_2026-11-12.md): official pinned libXray Apple archive SHA-256 and pinned `go.mod` SHA-256, upstream source tag/60 dependencies, ZIP traversal/symlink/substitution tests.
- [x] Физический iPhone **не используется**: отдельный native lab Swift adapter уже подтверждён в iOS Simulator на семи последовательных/конкурентных start/stop циклах с `blackhole` outbound; production PacketTunnel и App Store не изменены.
- [ ] Осталось: реальный original-flow PacketTunnel egress, физический iPhone Keychain/QR/CloudKit/device network-path, native reproducible SBOM и signed release gate. Пока активна только опубликованная 0.2.0, следующий номер 0.3.0 ещё не отправлен Apple.


## Состояние 12.11 после завершения работы без iPhone

- [x] PR #361 merged, exact-head CI 17/17, canonical main `0afa59fcb369bc40dcfd2e4f6af53ce61f4f3f26`; Mac mini/GitHub/GitVerse parity.
- [x] Swift226/226, Python307 +1513 subtests, unsigned Simulator ARM64 Debug и iPhoneOS ARM64 Release builds PASS.
- [x] iOS Simulator user journey импорта прокси PASS без реального VPN.
- [x] Изолированный DEBUG-only native PacketTunnel Rust+libXray handoff собирается для Simulator/iPhoneOS arm64, native blackhole lifecycle проверен; исходный libXray не добавлен в production.
- [ ] **Аппаратный блокер**: реальный iPhone original-flow nonce receipts, Keychain/QR/CloudKit, реальные VLESS и стандартный WG handshake; licensing/reproducible native build отдельно. До физической приёмки новые протоколы не доступны и 0.3.0 не публикуется.

## Keychain migration gate, 12.11.2026

- [x] После разрешённого in-place QA обновления 0.2.0→Debug 0.3.0(49) отдельный подписанный unit-test на физическом iPhone13 подтвердил 3/3 доступных непустых Keychain-пароля. Отсутствуют сетевые операции и раскрытие секретов.
- [x] Повторно сравнили App Group prefs: список трёх профилей и выбранный ID идентичны оригинальному post-install снимку.
- [ ] Реальный authenticated proxy egress, DNS, IPv4/IPv6/UDP, облачный opt-in и native VLESS/WG/AmneziaWG приёмка — ещё не выполнены.
