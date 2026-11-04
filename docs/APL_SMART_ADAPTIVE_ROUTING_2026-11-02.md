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

## Новый этап: APL-SMART3-SENSOR-001 выполнен (02.11)

- `Tools/tun2proxy-flow-intent.patch`: воспроизводимый source-pinned Rust `tun2proxy` с новым `flow_events.rs` и `tun2proxy_set_flow_event_callback` (C ABI). События: **0** успешный CONNECT к домену, **1** timeout (в том числе 12-секундный предел handshake), **2** TCP connection refused, **3** прочий отказ рукопожатия (НЕ свидетельство необходимости DIRECT), **4** недоступность исходного прокси (глобальная ошибка, НЕ разрешение). Имя происходит **только** из виртуального DNS конкретного TCP-потока; без TLS payload, HTTP-страниц и произвольных IP/SNI/URL. Для разных TCP-подключений отдельный `uint64` ID.
- `PacketTunnel/SmartFlowEventCollector.swift`: синхронно регистрирует C callback при запуске движка, снимает при отключении VPN; события обрабатываются на отдельной последовательной очереди, hostname копируется до возврата из C; проверяет успешные CONNECT **к другим доменам за последние 60 с** как минимальное условие здорового прокси. Только после двух ошибок конкретного домена вызывает local-only `AdaptiveRouteLearning`, не включает DIRECT без доказанного независимого egress. Не сохраняет исходные IP, пароль прокси, содержимое запросов и точные URL в логах. Нераспознанные ошибки не считаются доказательством блокировки.
- `ExclusionsView`: новый раздел «Проблемные сайты» показывает свежую рекомендацию (до 120 с), если APL наблюдала повторные TCP-сбои конкретного имени. Нажатие «Проверить исключение» открывает существующее **явное предупреждение об общем IP**, затем пользователь может разрешить исключение. В отсутствие подтверждения никакой IP-wide DIRECT не создаётся. Никакого сервера/Gateway и новой регистрации VPN нет.
- Сборочный сценарий `fetch_tun2proxy.py` воспроизводимо добавляет C-ABI header для обоих slices; ARM64 device+Simulator статические библиотеки компилируются. `nm` подтверждает exported callback; iOS Simulator app linked BUILD SUCCEEDED, **126/126 Swift Core**, **10/10 Rust**, **17/17 Python**, **1/1 новый UI XCTest** PASS. DEBUG fixture для UI теста не входит в Release.

**Существенная граница:** успешный HTTP CONNECT означает только готовность прокси перенаправить TCP, а не работоспособность сайта/авторизации. Если сайт отвечает `403` внутри TLS или зависает после загрузки JS, Packet Tunnel не увидит этот факт. Поэтому автоматизация по одному только сетевому событию не может гарантировать спасение всех сайтов.

**Аппаратная приёмка 02.11:** [Физический iPhone, истинные TCP CONNECT тайм-ауты и возврат к исходному приложению](APL_SMART3_PHYSICAL_IPHONE_QA_2026-11-02.md). Две реальных ошибочных TCP-сессии сохранены локально, но никаких новых автоматических DIRECT маршрутов не создано; восстановлены прежняя сборка и профили. Диагностическая Wi-Fi/Cellular TLS-проверка протестирована отдельно, **не доказывает независимый noproxy egress**.

## Что принципиально ещё НЕ работает на текущем iPhone

Apple [TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers) не рекомендует передавать захваченные Packet Tunnel соединения через другой интерфейс или размещать локальный прокси в расширении. [Routing your VPN network traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic) описывает `excludedRoutes` **по IP**, не по имени сайта. «Сделать на секунду noproxy ради пробника» в этой модели может выпустить посторонний трафик к тому же CDN IP. Это противоречит предыдущему требованию к безопасности. Safari TLS также скрывает HTTP/JS ошибки, поэтому прокси может корректно открыть TCP, хотя страница всё ещё не работает.

## Задачи до реальной автоматизации

- **`APL-SMART3-SENSOR-001`:** per-host callback реального TCP CONNECT timeout/refused и успешного CONNECT из исходников pinned Rust `tun2proxy` → Swift/App Group; не сохранять raw URLs, credentials, историю посещений, IP пользователя. Проверить против работающего прокси и двух виртуальных HTTPS хостов.
- **`APL-SMART3-EGRESS-001`:** доказать поддерживаемый Apple независимый исходящий DIRECT-пробник и **per-flow exact-host routing** без IP-wide collateral, либо документировать невозможность на consumer iOS. Не подменять это `NWConnection(requiredInterface)` без реальной верификации. Если платформа не позволяет: на iOS предлагать пользователю ручное исключение с ясным предупреждением, а полностью автоматическую ветку реализовать на Windows/macOS, где есть нужные системные перехваты.
- **`APL-SMART3-DEVICE-001`:** физический iPhone, реальный A → auth.A, два отдельных egress, DNS/IPv6/UDP, Wi-Fi/LTE, отсутствие утечки при shared-IP, откат и сохранение профилей.

**Статус:** механизм оценки и памяти подготовлен и протестирован. **Автоматически определять проблемы Safari и переводить домены в DIRECT на iOS пока НЕ умеет.** Никакого Apple upload, изменения действующего VPN/iPhone, рекламы, privacy label или прокси не выполнялось. Не отмечать пользовательскую Smart 3.0 функцию как завершённую.

## Физический аппаратный тест (02.11.2026)

[Протокол настоящего iPhone 13](APL_IOS_SMART3_PHYSICAL_EGRESS_QA_2026-11-02.md): проверена цепочка per-host TCP CONNECT → Local App Group evidence (две сессии), независимый TLS Wi-Fi probe при APL VPN включён и proxy mock отказывает этому же hostname, 20–25-секундный автоматический rollback. Original signed debug app и сохранённые данные возвращены. Автоматический точный bypass Safari **не реализован**, поскольку проверка отдельного TLS-сокета не заменяет поддерживаемое физическое per-flow перенаправление.

## Дополнение 03.11.2026 — минимальное взаимодействие и проверка Apple API

- При возвращении из Safari APL теперь перечитывает локальные сведения App Group о недавних сетевых сбоях (`ContentView.onChange(scenePhase == .active) → AppViewModel.refresh()`). Если есть актуальный домен с минимум двумя подтверждёнными ошибками, вкладка **«Настройки»** показывает числовой badge. Он не появляется для устаревших либо запрещённых пользователем кандидатов, не требует push permission, фонового опроса или доступа к истории Safari; кнопка остаётся ручной с предупреждением об общем IP. Нет дополнительных рекламных блоков или смещения главных кнопок.
- Уточнённый анализ официальных механизмов Apple: `NEOnDemandRuleEvaluateConnection` / `NEEvaluateConnectionRule.neverConnect` регулируют **надо ли запускать VPN**, но не исключают отдельный домен из уже активного полного Packet Tunnel. `NETunnelProviderManager.excludedDomains` относится **только к per-app VPN**, а iOS per-app VPN и `NEAppProxyProviderManager` требуют MDM-managed `com.apple.vpn.managed.applayer`. `NEPacketTunnelNetworkSettings.excludedRoutes` задаёт маршруты **по destination-IP**. `NEPacketTunnelProvider.createTCPConnectionThroughTunnel` предназначен для подключения **через туннель**, не обеспечивает DIRECT на физическом интерфейсе. Всё это не заменяет поддерживаемую consumer iOS domain-scoped split-egress.
- [Apple TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers), [Routing VPN traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic), [NEOnDemandRuleEvaluateConnection](https://developer.apple.com/documentation/networkextension/neondemandruleevaluateconnection), [excludedDomains](https://developer.apple.com/documentation/networkextension/netunnelprovidermanager/excludeddomains), [NEAppProxyProviderManager](https://developer.apple.com/documentation/networkextension/neappproxyprovidermanager) являются источниками платформенного решения.

**Следствие для iOS 0.2.0:** автоматическая диагностика и рекомендация могут быть доведены до релизного качества, но нельзя обещать автономное безопасное переключение Safari на DIRECT по имени сайта без смены системной сетевой архитектуры либо явно принятого изменения требований. Пользователь ранее отклонил удалённый Gateway и требует избежать выхода сторонних сайтов на том же IP. Не менять эти ограничения без владельца. Полный Smart 3.0 по исходному DoD остаётся release blocker.

### Аппаратная приёмка дополнения 03.11.2026

На спаренном физическом iPhone 13 (iOS 27.2) проверен `SmartExclusionsUITests.testSmart3ProblemBadgeAndNoSilentExclusion`: **PASS (12,919 с)**. In-memory DEBUG fixture создала две синтетические TCP ошибки `auth.qa-example.test`; вкладка «Настройки» показала badge 1, внутри рекомендация обнаружена, отсутствие silent direct/нового исключения подтверждено. На рабочий прокси/VPN тест не переключался. После окончания прежняя подписанная APL **0.2.0 (48)** восстановлена с успешным результатом CoreDevice.

Перед повторной установкой исходный `.app` был сохранён; после восстановления App Group preferences снова скопированы для сравнения. **Шесть ключей сохранённых профилей/выбора/исключений совпадают побайтно** (`profiles.v1`, `selected_profile_id`, `primary_profile_id`, `manual_site_exclusions.v2`, `smart_dependency_graph.v1`, `site_exclusions`); остальные три изменения UserDefaults не относятся к этим данным. Подписанная версия не изменилась, PacketTunnel process не запущен. Никакие значения профилей, пароли и личные данные не записаны в Git.

Симулятор: **2/2 UI XCTest PASS**, Swift Core **126/126 PASS**, Python source contracts **23/23 PASS**, iOS 0.2.0(48) preflight PASS. Функциональное ограничение остаётся прежним: низкорисковая рекомендация вместо неподдерживаемого zero-touch exact-host DIRECT.
