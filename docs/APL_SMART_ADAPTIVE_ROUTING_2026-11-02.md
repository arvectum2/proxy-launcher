# Smart Exclusions 3.0 — адаптация маршрутов к сбоям

**02.11.2026**, задача `APL-SMART-ROUTE-LEARNING-20261102`, iOS 0.2.0 (48), Draft PR #296. **Без Gateway/VPS.** Пользователь хочет открыть A, нажать «личный кабинет», перейти на `auth.A` и не добавлять `auth.A` вручную, если через прокси он недоступен, а напрямую доступен.

## Целевое поведение

1. `tun2proxy` определяет точный DNS-host нового TCP-потока через `VirtualDns`. Отличает ошибки HTTP CONNECT/SOCKS `connection timed out/refused` от общего отказа прокси, ошибок TLS, ошибок браузерной страницы, HTTP 4xx/5xx и UDP. **Содержимое TLS и зависание страницы в Safari PacketTunnel не видит.**
2. Две ошибки **разных** TCP-подключений к конкретному hostname за 120 секунд при работающем основном прокси → запрос на независимую DIRECT-проверку. Один повторяющийся callback или сбой всего прокси не основание менять маршрут. Повторные пробы не чаще 1 раза/60 с.
3. Нужны два достоверных A/B сравнения: прокси к домену всё ещё не работает, а DIRECT работает и действительно использует внешний путь **вне VPN**, при корректной проверке TLS hostname. Доступность через тот же APL VPN не доказательство DIRECT.
4. Только если система **умеет точно маршрутизировать имя отдельного потока, не раскрывая чужие сайты на том же CDN IP**, включить DIRECT на 24 часа. При смене сети, истечении TTL, отзыве или неудаче — вернуть PROXY. Не больше 12 автоматических правил; не подменять ручные исключения.

## Что реализовано и проверяется

- `mobile/ios/SharedCore/AdaptiveRouteLearning.swift`: локальный Codable state machine — уникальные TCP-сбои, cooldown, A/B и два успеха, TTL 24 часа, rollback, пользовательский запрет, игнорирование tracking/analytics и TLS/application-only ошибок, пределы ресурсов.
- `mobile/ios/SharedCore/AdaptiveRouteCapabilities.swift`: обе iOS-возможности `iosIndependentNoProxyProbe`, `iosPacketTunnelExactHostDirect` **равны false** до подтверждения платформенной поддержки.
- `mobile/ios/Shared/ProfileStore.swift`: опциональная локальная App Group запись `smart_route_evidence.v1` максимум 64 KiB, не передаёт историю в облако и не изменяет `siteExclusions` или Keychain. Пока в неё не пишутся данные реального сетевого потока: сенсор отсутствует.
- `AdaptiveRouteLearningTests.swift` проверяет переходы, дедупликацию, throttle, отдельный домен на том же IP, истечение TTL, смену сети и rollback. Существующий автопоиск зависимостей A→B/C не изменён.

## Что принципиально ещё НЕ работает на текущем iPhone

Apple [TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers) не рекомендует передавать захваченные Packet Tunnel соединения через другой интерфейс или размещать локальный прокси в расширении. [Routing your VPN network traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic) описывает `excludedRoutes` **по IP**, не по имени сайта. «Сделать на секунду noproxy ради пробника» в этой модели может выпустить посторонний трафик к тому же CDN IP. Это противоречит предыдущему требованию к безопасности. Safari TLS также скрывает HTTP/JS ошибки, поэтому прокси может корректно открыть TCP, хотя страница всё ещё не работает.

## Задачи до реальной автоматизации

- **`APL-SMART3-SENSOR-001`:** per-host callback реального TCP CONNECT timeout/refused и успешного CONNECT из исходников pinned Rust `tun2proxy` → Swift/App Group; не сохранять raw URLs, credentials, историю посещений, IP пользователя. Проверить против работающего прокси и двух виртуальных HTTPS хостов.
- **`APL-SMART3-EGRESS-001`:** доказать поддерживаемый Apple независимый исходящий DIRECT-пробник и **per-flow exact-host routing** без IP-wide collateral, либо документировать невозможность на consumer iOS. Не подменять это `NWConnection(requiredInterface)` без реальной верификации. Если платформа не позволяет: на iOS предлагать пользователю ручное исключение с ясным предупреждением, а полностью автоматическую ветку реализовать на Windows/macOS, где есть нужные системные перехваты.
- **`APL-SMART3-DEVICE-001`:** физический iPhone, реальный A → auth.A, два отдельных egress, DNS/IPv6/UDP, Wi-Fi/LTE, отсутствие утечки при shared-IP, откат и сохранение профилей.

**Статус:** механизм оценки и памяти подготовлен и протестирован. **Автоматически определять проблемы Safari и переводить домены в DIRECT на iOS пока НЕ умеет.** Никакого Apple upload, изменения действующего VPN/iPhone, рекламы, privacy label или прокси не выполнялось. Не отмечать пользовательскую Smart 3.0 функцию как завершённую.
