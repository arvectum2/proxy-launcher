# Единый транспортный движок APL iOS 0.3.0: Xray VLESS/Reality + стандартный WireGuard

**Статус 12.11.2026: техническая гипотеза с успешно пройденными локальными iOS-симуляторными и link-тестами. НЕ готово для production и не является физическим VPN-подключением.**

## Подтверждённая инженерная возможность

- Xray-core включает исходный клиентский WireGuard outbound: `https://github.com/XTLS/Xray-core/tree/main/proxy/wireguard`; генератор конфигурации `https://github.com/XTLS/Xray-core/blob/main/infra/conf/wireguard.go` поддерживает `secretKey/address/peers/allowedIPs/noKernelTun`.
- Официальная `XTLS/libXray v26.11.9` для Apple iOS arm64 и Simulator зафиксирована SHA256 `7c58346709f1856782a48d8f9926fb815c8ad1bbaf9e5d9dec4ee0cd1f41ed6f`, скачана только в отдельный R&D каталог.
- В **реально запущенном ARM64 iOS Simulator** `CGoInvoke` API v3 `testXray` принимает синтетическую конфигурацию `protocol=wireguard` с `noKernelTun=true` и встроенным userspace TCP/IP stack (успех).
- В симуляторе прошла последовательность `testXray → runXray → getXrayState(running=true) → stopXray → getXrayState(running=false)` для локального SOCKS inbound `127.0.0.1:39871` и фиктивного WireGuard peer **только на loopback `127.0.0.1:39873`**. Ни одной успешной внешней WG handshake не утверждается.
- Ранее на том же Simulator подтверждены `libXray` VLESS/Reality config conversion и локальный синтетический HTTP receipt через SOCKS. Это не трафик из PacketTunnel.
- В отдельном `research/ios-030-xray-native-link-20261112` успешно собраны **unsigned iOS Simulator Debug ARM64 и iPhoneOS Debug ARM64** App+PacketTunnel c Rust `tun2proxy` и Go `libXray`; в обоих бинарниках `nm` подтверждает `_tun2proxy_stop`, `_CGoInvoke` и test-only symbol. Компоненты не включены в production main.
- Первоначальный Xcode link провалился из-за двух `include/module.modulemap`; изолированная ручная platform-specific статическая линковка libXray устранила конфликт. Потребуется воспроизводимый post-licensing build/copying pipeline, а не symlink на частный кэш.

## Рекомендуемая архитектура

1. Единственная существующая `NEPacketTunnelProvider` продолжает читать TUN packets через Rust `tun2proxy`. Для поддерживаемого `HTTP/HTTPS/SOCKS5` никаких изменений маршрутизации.
2. Для Xray-профилей *только после QA* запускается один Go-runtime `libXray` внутри того же PacketTunnel. `tun2proxy` использует проверенный `127.0.0.1:<ephemeral>` SOCKS5 inbound Xray; Xray управляет соответствующим VLESS/REALITY либо WireGuard outbound.
3. Внедрить строгий выбор backend на сессию, возврат оригинальных настроек, управление жизненным циклом, таймаут и отмену, исключение собственных UDP/TCP сокетов движка из TUN, защита от рекурсии loopback, fail-closed переходы, DNS/IPv6 и stop-drain. Не добавлять production `ProxyType` до внешних независимых receipt.
4. Ключи WG и токены VLESS хранятся в Keychain; конфиги формируются в памяти и не попадают в Activity, os_log, App Group plaintext или облако. Предварительный `WGQuickConfigurationPreview` по-прежнему **не сохраняет ключи** и не является импортом рабочего VPN.
5. Включение wireguard outbound Xray позволяет **избежать второго Go-runtime** для стандартного WireGuard. Но AmneziaWG 1/2/3 **не признан поддерживаемым Xray** без отдельного подтверждения: его возможный backend надо изолировать (отдельное NE extension/альтернативный runtime), не подменять WireGuard.
6. Произвести лицензионный audit конкретного libXray/Xray-core source (MIT/MPL-2.0) и транзитивных зависимостей, фиксировать SHA/SBOM, размер App Extension и память (debug PacketTunnel dylib около 43 МБ).

## Следующие gates

- [ ] DEBUG-only реальный PacketTunnel original-flow → tun2proxy → localhost Xray SOCKS → независимый VLESS/WG внешний endpoint с nonce witness; без изменения текущих профилей.
- [ ] Восстановление после force-stop, 5xx/timeout, переключения Wi-Fi/LTE, DHCP/IPv4/IPv6 и QUIC/UDP; запрет утечки DNS/traffic при ошибке.
- [ ] На физическом тестовом iPhone подписанный IPA с отдельным профилем/конфигурацией, без перезаписи работающих профилей, явное подтверждение пользователя для потенциально рискованных действий.
- [ ] Новые протоколы в UI и App Store metadata только после всех вышеперечисленных проверок.
- [ ] CloudKit capability, приватный container, opt-in и двухустройственная проверка отдельным acceptance gate.

**Главное:** локальный loopback receipt и синтетический WireGuard `runXray` доказывают работу нативного Go-движка в iOS Simulator, но НЕ фактическую работу зашифрованного туннеля или соответствие App Store.
