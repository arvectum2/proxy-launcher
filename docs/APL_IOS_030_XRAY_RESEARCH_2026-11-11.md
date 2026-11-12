# APL iOS 0.3.0 — VLESS/REALITY: проверенное исходное исследование

Дата: 2026-11-11. **Исследовательская готовность, не поддерживаемый протокол и не разрешение на выпуск.**

## Конкретный нативный кандидат

- `XTLS/Xray-core`, лицензия MPL-2.0: https://github.com/XTLS/Xray-core
- `XTLS/libXray`, оболочка MIT с транзитивным Xray-core: https://github.com/XTLS/libxray
- Версия выпущенной Apple CGO сборки: `XTLS/libXray v26.11.9`; исходный tag SHA `71d9d443aa88ff939ab6ce22b82aa4b2adcc4d9f`.
- Отдельно загружен официальный asset `libxray-apple-cgo.zip` (102,548,590 bytes на GitHub); **SHA256 совпал с release asset digest**: `7c58346709f1856782a48d8f9926fb815c8ad1bbaf9e5d9dec4ee0cd1f41ed6f`.
- Локальный R&D asset и каталог вне репозитория: `/Volumes/ArvectumSSD/Arvectum/worktrees/apl-ios-030-vless-research-20261111/`. **Не в Git, не в App Store bundle**.
- Архив содержит `LibXray.xcframework` iOS arm64 и iOS Simulator arm64/x86_64 с C API: `CGoInvoke(char *requestJSON)` и `CGoFree(char *value)`, а также другие платформы.
- Документация Xray-core сообщает поддержку iOS TUN из fd NetworkExtension, включая `xray.tun.fd`/ `XRAY_TUN_FD` и требования к исключению собственных сокетов из туннеля: https://github.com/XTLS/Xray-core/blob/main/proxy/tun/README.md . **Наличие документации не доказывает работоспособность на наших entitlements/сетях**.

## Границы внедрения

1. Сначала прочитать подписанный pinned source libXray invoke API; составить один корректный `start/stop` жизненный цикл и zero-secrets logging; проверить, что libXray/Xray-core и другие Go-библиотеки *не* загружают два независимых Go runtime в один PacketTunnel процесс.
2. Для VLESS/Reality введён типизированный *неактивный* валидатор `VLESSRealityShareLink` (REALITY+TCP/vision, строгий pubkey/UUID/SNI, URL bounds, фильтр неизвестных параметров) и CGoInvoke v3 запрос на конвертацию; существующий `ProxyType` HTTP/HTTPS/SOCKS5 не менялся. Конфигурацию Xray строит только pinned libXray, а не наш самодельный JSON.
3. Базовый безопасный исследовательский маршрут: оставить capture в существующем `tun2proxy` и подключить его SOCKS5 upstream к **локальному** Xray SOCKS inbound (тот отправляет наружу через VLESS/REALITY). Это избегает извлечения приватного/непубличного PacketTunnel fd. **Но этот совместный маршрут ещё не интегрирован и не доказан на iPhone**: собственные outbound-сокеты Xray обязаны обходить петлю туннеля, а `stop`, failover, DNS, rollback и ресурсы PacketTunnel требуют аппаратной проверки.
4. Проверить legal notices, конкретный source/tag, транзитивный SBOM, память и размер, воспроизводимую сборку. На Mac mini команда `go` пока недоступна в PATH, поэтому официальный asset годится лишь для исследовательского линкования и API PoC, не для финального build provenance.
5. Проверить реальные iPhone egress на VLESS/REALITY server, IPv4/IPv6/UDP, reconnect, Wi-Fi/LTE, сохранение credentials и CoreDNS path; до физических доказательств Xray НЕ подключается к production UI и не попадает в подписанную IPA.
6. Отдельно оценить WireGuardKit + WireGuardGoBridge и AmneziaWG bridge, не смешивать Go runtimes в одном процессе без обоснованной архитектуры.

Проверка собственного кода APL: **никаких новых runtime dependencies и changes to the production PacketTunnel в этом R&D этапе**.


## Выполненные изолированные iOS Simulator R&D тесты — 11.11.2026

- [x] `libxray-apple-cgo.zip` `v26.11.9` SHA256 == GitHub release digest; XCFramework содержит arm64 iPhoneOS + arm64/x86_64 Simulator.
- [x] C bridge `CGoInvoke`/ `CGoFree` успешно слинкован в отдельный ад-хок подписанный ARM64 Simulator executable без приложения и без учётных данных.
- [x] На **запущенном** iOS Simulator метод `xrayVersion` API v3 вернул `26.11.9`.
- [x] На том же симуляторе синтетическая (публичные example.com/нулевой ключ) VLESS/REALITY ссылка через `convertShareLinksToXrayJson` вернула `success=true` и `outbounds[0].protocol=vless`, `streamSettings.security=reality`. Это **парсинг**, не реальный TLS handshake.
- [x] Пять вызовов API `testXray → runXray → getXrayState(true) → stopXray → getXrayState(false)` PASS для локального SOCKS inbound 127.0.0.1:39871 и `freedom` outbound. Один стартовый warning/Xray log не является JSON ответом.
- [x] Через запущенный в iOS Simulator libXray SOCKS inbound проксирован `curl --socks5-hostname` до синтетического HTTP сервера на localhost (127.0.0.1:39872); получен точный одноразовый тестовый receipt `APL_SYNTHETIC_LOOPBACK_ONLY_20261111`. **Это локальная петля, не PacketTunnel egress / физический VPN.**
- [x] После R&D оба симуляторных устройства shutdown, тестовый HTTP сервер остановлен, все Go и C артефакты **вне git / вне IPA**.
- [x] Typed `VLESSRealityShareLink` не меняет production `ProxyType`; 6/6 новых Swift Core tests и 3/3 iOS gate Python tests проверяют fail-closed поведение. Full Swift213/213, iOS Python295 +1513 subtests, unsigned ARM64 iOS Simulator Debug и iPhoneOS Release App+PacketTunnel BUILD PASS.
- [ ] Влияние на память PacketTunnel, лицензии всех transitive dependencies, производственный native bridging, реальный VLESS/REALITY server, IPv4/IPv6/UDP, Wi-Fi/LTE и Smart4 egress **не проверены**.
- [ ] Физический iPhone по текущему `devicectl` на Mac mini обозначен `unavailable`; **никаких физических испытаний или VPN переключений в этом этапе не проводилось**.
