# APL-SMART-FLOW-001 — доменная политика каждого соединения и iOS feasibility gate

**Дата:** 02.11.2026 · источники: tun2proxy **v0.8.3**, pinned source `e271de19683937f23d3f8f0eb4df0a61fc4a6e50`; iOS 0.2.0 (48), Draft PR #296. **Статус: реализован и собран экспериментальный per-flow classifier, физический DIRECT на iOS НЕ реализован и НЕ активирован.**

## 1. Вывод исследования Apple

Документация Apple: [TN3120 Expected use cases for NE packet tunnel providers](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers) **явно не рекомендует** (a) hosting local listener/proxy server in Packet Tunnel и (b) выборочное перенаправление захваченного трафика через иные интерфейсы/прокси. [NEPacketTunnelProvider](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider) и [VPN routing](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic) оперируют **маршрутами по destination IP**, а не произвольным exact-host split tunnel для consumer iOS. Свойство [NWParameters.requiredInterface](https://developer.apple.com/documentation/network/nwparameters/requiredinterface) существует, но **не означает**, что построенный на нём Packet Tunnel local-listener/proxy является поддерживаемым сценарием.

Поэтому гипотеза `TUN → local HTTP/SOCKS listener → NWConnection(requiredInterface) → direct Internet` **не принимается** в iOS release без формального подтверждения Apple и аппаратного egress proof. Мы не добавляем такой listener в расширение и не меняем реальные VPN-профили владельца.

## 2. Что реализовано сейчас — безопасный прототип Rust

`mobile/ios/Tools/tun2proxy-flow-intent.patch` — **отдельный воспроизводимый patch к исходному v0.8.3 + существующему `tun2proxy-split-dns.patch`**. `fetch_tun2proxy.py` теперь применяет оба патча последовательно с `git apply --check` и фиксирует имя патча в rebuild marker.

`src/flow_routing.rs` внутри патча:

- Строгие ASCII IDNA DNS-лейблы exact-host; запрещены wildcard, suffix rule, literal IP, пробелы, `:port` и недопустимые DNS-метки; регистр и завершающая точка нормализуются.
- **Новая TCP-сессия** сопоставляется с hostname по уже имеющемуся в `tun2proxy` `VirtualDns.resolve_ip(fake IP)`. Входом **не являются** неподтверждённый HTTP Host/SNI, реальный общий IP, DNS для другого потока и запросы стороннего приложения. Одинаковый физический CDN IP не объединяет две независимые DNS identity.
- `FlowIntent::DirectNeedsScopedTransport` — **только кандидат**, **не разрешение** на unscoped TCP socket. `FlowIntent::Proxy` — default, для неизвестного/неразрешённого, невалидного, raw-IP и всех потоков без synthetic-DNS attribution.
- Экспериментальный CLI `--flow-direct-candidate EXACT_HOST` парсится/проверяется, **в release iOS не передаётся**. На ingress движок классифицирует, но всё равно выбирает **существующий upstream-proxy manager**. Ни одна экспериментальная ветка не создаёт DIRECT соединение.
- Разграничение TCP-identity проверено для `site.test`, `api.site.test`, `static.site.test` и неразрешённого `tracker.other.test` с одинаковым предположенным публичным IPv4/IPv6. Истинное назначение ещё **не проверено** в iPhone VPN/Network Extension.

В отличие от `SharedIPRouteGuard` с негативным IP-collision filter, это точка развития точной сетевой политики **не на IP**, но пока **не способ доставки DIRECT**. Оба механизма существуют независимо: продакшн Packet Tunnel пока продолжает старый `--dns-bypass` и `NEIPv4/NEIPv6.excludedRoutes` плюс коллизионный guard. **Уязвимость неизвестного shared-host в текущей реализации остаётся**; нет оснований отмечать Smart Exclusions 2.0 как DONE.

## 3. Проверка воспроизводимости и фактические артефакты

- Rust `cargo +1.98.1 test --lib --locked`: **8/8 PASS**, в том числе 3 exact flow/CLI теста и 3 ранее существовавших virtual DNS regression tests.
- `git apply --check` и применение доп. патча на отдельной чистой локальной копии уже-patched pinned v0.8.3: **PASS**, файлы `src/{args,lib,flow_routing}.rs` полностью совпали с тестируемыми исходниками.
- Rust cross-compile для `aarch64-apple-ios` и `aarch64-apple-ios-sim`: **PASS** на pinned toolchain, SHA256 бинарных локальных `.a` записаны в QA-лог; оригинальный `Frameworks` — игнорируемые rebuild артефакты, новый исходный patch и script коммитятся в Git.
- iOS Simulator `xcodebuild` с locally rebuilt **обоими** статическими Rust slices: **BUILD SUCCEEDED**. Изменения не включают new entitlements, локальный прокси listener, Apple review/advertisement/privacy.

## 4. Предметная следующая задача: поддерживаемый транспорт / acceptance

**`APL-SMART-FLOW-002` — PLATFORM FEASIBILITY GATE**, блокирует включение DIRECT в пользовательский релиз. До разработки выбрать **один поддерживаемый Apple транспортный/продуктовый путь**; варианты:

1. Поддерживаемая Apple схема с `NEPacketTunnelProvider` — запросить у Apple Developer Technical Support явное подтверждение применимости *exact-host local direct egress* **внутри** Packet Tunnel. Без такого подтверждения не внедрять локальный listener/подмену интерфейса.
2. Если Apple не поддерживает этот сценарий — разделить продуктовые режимы: обычные **явные IP-wide исключения** с честным предупреждением и консервативную **strict-proxy/no-leak** политику без direct для доменов на неизвестном CDN IP, либо iOS **per-app VPN через MDM** там, где это разрешено. Выбор связан с UX-совместимостью и требует решения владельца.
3. При наличии разрешённого API и тестового iPhone/прокси — доказать два TLS-hosts на одном IPv4 и IPv6 с разными выходными интерфейсами/IP (approved html/css/js/api DIRECT, denied PROXY), DNS rebinding, DoH, QUIC/UDP, Wi-Fi/LTE, failover/rollback, отсутствие утечки proxy credentials и повторную подстановку `--dns-bypass`/legacy routes. Сырой DNS/Python лабораторный тест не заменяет этот proof.

**Definition of Done:** входное host-policy решение и фактический outbound transport для каждого потока, независимое доказательство выхода, запрет global IP-route для доменов, iOS физический E2E и отсутствие нарушений платформенных контрактов. До этого `APL-SMART-FLOW-001` / Smart Exclusions остаются **blocked**, даже если все source/Simulator тесты зелёные.
