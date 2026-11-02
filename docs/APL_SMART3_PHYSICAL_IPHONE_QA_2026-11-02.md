# Smart 3.0 — аппаратная проверка iOS Packet Tunnel и пробного TLS

**02.11.2026** · iOS 0.2.0 (48), физический iPhone 13 (iOS 27.2), Mac mini, **без публикации/изменения пользовательских прокси**. Все аппаратные проверки выполнялись с явного разрешения владельца. Эта проверка НЕ аттестует автоматический DIRECT и не снимает release gate.

## До теста и после

- `devicectl` подтвердил paired/connected физический iPhone; текущее приложение APL 0.2.0 (48). Подписанная Development-сборка собрана и проверена `codesign --verify --deep --strict`.
- Перед тестом сохранены пользовательская App Group `group.ru.arvectum.proxylauncher.ios` и настройки приложения в приватной локальной папке Mac mini, права 0700/0600. Никакие значения профилей, логины, IP поставщиков и proxy passwords не публиковались.
- После проверок удалено только синтетическое `smart_route_evidence.v1`, если в нём **исключительно** тестовые хосты `.qa-example.test` и нет отказов пользователя. Проверено экспортом App Group: исходных 10 ключей и 10 ключей после очистки; тестового evidence нет; реальные profile records побайтово совпали с резервной копией. QA изменила диагностические `profile_quality`/`tunnel_events`, но не содержание пользовательских профилей.
- На устройство обратно установлен сохранённый исходный подписанный Debug app bundle 0.2.0 (48). Актуальные параметры VPN и прокси пользователя не перезаписывались вручную.

## Протокол реального сетевого теста

1. На Mac mini создан **одноразовый** HTTP CONNECT proxy на частном LAN-интерфейсе, который не передаёт трафик в Интернет: разрешён исключительно синтетический `probe.qa-example.test:443` (CONNECT 200), для `auth.qa-example.test:443` ответ задерживается 13,8 секунды, все остальные соединения немедленно отвергаются 403 без логирования чужих destination hosts. Сервер сам выключается через максимум 115 секунд. Воспроизводимый источник: `scripts/qa_smart3_local_proxy.py`.
2. На iPhone по DEBUG-only временным launch arguments `-aplEphemeralTunnelQA -aplSmart3LocalProxyQA` создана **не сохраняемая** в профили APL тестовая конфигурация HTTP proxy. Safety timer Packet Tunnel вызывает `cancelTunnelWithError` в течение не более 25 секунд, независимо от тест-раннера. Test runner также отключает за 20 секунд.
3. **Реальные TCP/CONNECT-соединения**, не только UI-фикстура: в тестовом прокси зафиксированы **2 разрешённых синтетических CONNECT**; App Group на физическом iPhone содержала **1 host с двумя различными `sessionIDs`**, подтверждая путь `Network.framework/TUN → Rust tun2proxy → C callback → Swift SmartFlowEventCollector → ProfileStore`. Direct route не был включён (`expires` отсутствует). Остальные системные попытки были отвергнуты локальным тестовым proxy; платный upstream не использовался.
4. Hardware `Smart3LiveTunnelPhysicalUITests.testLiveVPTunnelPerHostCONNECTSignalWithAutoRollback`: **PASS**, реальный Packet Tunnel тест завершился. `SmartExclusionsUITests.testAdaptiveConnectionSuggestionRequiresManualConsent`: **PASS** на телефоне, проверено отсутствие silent bypass. `AdaptiveDirectProbePhysicalUITests.testPhysicalTLSProbeDisplaysBoundedDiagnostic`: **PASS** на телефоне, проверена явная неопределённость маршрута.
5. `AdaptiveDirectProbe` выполняет ограниченное TLS-подключение через `NWParameters.requiredInterfaceType` (Wi-Fi, затем cellular) с `currentPath.usesInterfaceType`. Важное ограничение: **физический тип интерфейса и успешный TLS handshake не доказывают, что egress произошёл вне VPN**; не используются как доказательство для автоматического добавления `/32`/`/128`. Отсутствие реального независимого egress/IP comparison — непройденный релизный критерий.

## Надёжность повторного аппаратного теста

Hardware test suites теперь требуют `APL_SMART3_HARDWARE_QA=enabled` в test runner environment, иначе **SKIP**. Это защищает от случайного запуска transient VPN на обычных прогонках. Сценарий QA в коде доступен только в DEBUG, только при двух совместных аргументах, только к фиксированному локальному адресу/порту и только в пределах 25 секунд. Публичного сервера, новых аккаунтов, системного VPN-конфига или платного прокси тест не создаёт. Тестовый скрипт требует явного `--bind` частного IPv4 и порта 18081. Для другого Mac потребуется переопределить DEBUG-адрес в исходниках и пересобрать QA-приложение. В production build этот путь недоступен.

## Результат / релиз

**Подтверждено на физическом устройстве:** обработка и запись реальных TCP-сбоев конкретного домена, отличный от ошибок глобального прокси; безопасное отсутствие автоматического исключения и сохранность пользовательских профилей. **Не подтверждено:** нативный Consumer iOS exact-domain DIRECT без IP-wide collateral; независимый Wi-Fi vs tunnel egress; браузерное содержимое HTTPS после логина, QUIC/UDP, динамический DNS и мобильный handoff. Следовательно **iOS 0.2.0 не готова к обещанному полностью автономному Smart 3.0**, и публикация не разрешается до платформенного/продуктового решения.

Нормативная база: [Apple TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers), [Routing your VPN network traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic), [NEAppProxyProviderManager](https://developer.apple.com/documentation/networkextension/neappproxyprovidermanager). Последний недоступен в unmanaged consumer VPN режиме: App Proxy конфигурации только MDM per-app.
