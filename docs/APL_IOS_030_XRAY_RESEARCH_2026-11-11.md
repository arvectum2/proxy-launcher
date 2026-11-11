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
2. Для VLESS/Reality создать безопасный парсер и профили, **отдельные от** существующего `ProxyType` HTTP/HTTPS/SOCKS5, и построение точного Xray JSON. Не переводить ссылки в старый HTTP/CONNECT.
3. Один реальный PacketTunnel должен выбирать ровно один backend (`tun2proxy` **или** Xray) на сессию; команда `stop`, timeout, отмена при смене конфигурации и rollback без DNS/traffic leak обязательны.
4. Проверить legal notices, конкретный source/tag, транзитивный SBOM, память и размер, воспроизводимую сборку. На Mac mini команда `go` пока недоступна в PATH, поэтому официальный asset годится лишь для исследовательского линкования и API PoC, не для финального build provenance.
5. Проверить реальные iPhone egress на VLESS/REALITY server, IPv4/IPv6/UDP, reconnect, Wi-Fi/LTE, сохранение credentials и CoreDNS path; до физических доказательств Xray НЕ подключается к production UI и не попадает в подписанную IPA.
6. Отдельно оценить WireGuardKit + WireGuardGoBridge и AmneziaWG bridge, не смешивать Go runtimes в одном процессе без обоснованной архитектуры.

Проверка собственного кода APL: **никаких новых runtime dependencies и changes to the production PacketTunnel в этом R&D этапе**.
