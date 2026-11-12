# APL iOS 0.3.0 — реальный PacketTunnel VPN, 12.11.2026

Площадка: физический iPhone13, iOS27.2.1, Xcode27.1; подписанная Development Debug APL0.3.0 (49). Согласованное QA с уже сохранённым профилем, без удаления приложения, импорта, изменения ключей или персональных данных.

## Safety gate

- Предварительная физическая проверка NetworkExtension из подписанного XCTest подтвердила исходное состояние APL OFF (NEVPNStatus.disconnected), затем после QA независимо подтвердила OFF повторно.
- UI XCTest не смог активировать Xcode automation mode и был отменён; это не тест продукта. Дальнейшая проверка сделана подписанным app-hosted unit-test, без управления экраном.
- Для реального теста требуется отдельный Swift-флаг APL_RUN_EXPLICIT_VPN_QA; обычная сборка App Store и CI его не имеют. На симуляторе тест всегда пропускается.
- Перед запуском оба независимых HTTPS IP witness (api.ipify.org и Cloudflare trace) дважды подтвердили стабильный прямой baseline. Значения публичных IP не выводились.
- Запуск производится только с уже сохранённым разрешённым NETunnelProviderManager в состоянии OFF; без создания и перезаписи конфигурации.
- Два kill switch: host-app DispatchWorkItem автоматически вызывает stopVPNTunnel через 20 секунд; PacketTunnel самостоятельно cancelTunnelWithError через 25 секунд. Дополнительно defer и штатный explicit stop.
- Туннель запускается с options requestedByUser=true, qaStopAfterSeconds=25, без иных QA-хостов или радио-переключений.

## Измерения

1. Первая проверка testBoundedAPLPacketTunnelChangesAndRestoresPublicEgress завершилась FAIL за 1.613s: тест ошибочно интерпретировал начальное Disconnected сразу после асинхронного startTunnel как окончательный отказ. Проверили независимым read-only XCTest, что VPN OFF, App Group profiles.v1 и selected UUID неизменны; исправили ожидание перехода.
2. Повторный аппаратный XCTest после исправления: PASS за **5.104s**.
3. PacketTunnel достиг Connected, оба watchdog были вооружены.
4. Пока VPN ON оба HTTPS witness показали смену внешнего адреса — **2/2**. Ни один IP не записывался в тестовые логи.
5. VPN выключен через stopVPNTunnel; статус OFF подтверждён внутри теста, оба witness показали восстановление прямого исходного адреса — **2/2**.
6. Отдельный последующий подписанный XCTest вновь подтвердил NEVPNStatus.disconnected — PASS за 0.008s.
7. После VPN CoreDevice повторно скопировал защищённые App Group preferences: 3 профиля, bytes profiles.v1 и selected_profile_id идентичны исходному снимку до испытания.

## Исходники и полный регрессионный набор

- [x] Симулятор с явным тестовым флагом APL_RUN_EXPLICIT_VPN_QA корректно пропустил физический тест: 1 skipped, 0 failed, TEST SUCCEEDED.
- [x] Полная локальная серия: Python321/321 +1513 subtests и Swift226/226 PASS.

## Что не доказывает этот тест

- Это физическое доказательство **реального PacketTunnel/TUN HTTPS egress + отключения и восстановления IP**, но не полной проверки DNS-leak, IPv4/IPv6 в разных сетях, UDP/QUIC, Wi-Fi/LTE handoff и fail-closed под обрывами.
- VLESS/Reality, standard WireGuard и AmneziaWG не интегрированы в подписанный пользовательский PacketTunnel и не проверены. CloudKit private entitlement и multi-device conflict также не готовы.
- Нет полноценного самостоятельного зашифрованного .aplbackup. Нельзя делать destructive rollback/uninstall; исходная iCloud Backup + защищённые метаданные не заменяют экспорт паролей.

Приватные логи на Mac mini: /tmp/apl030-physical-vpn-active-v2-20261112.log, /tmp/apl030-physical-vpn-poststate-v2-20261112.log. В репозиторий и чат не копировались IP, proxy-hostname, логины, пароли или UUID.
