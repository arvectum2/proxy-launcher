# Smart Exclusions 2.0: рабочий Gateway, разные сайты на одном IP

**02.11.2026**, Draft PR #296, ветка iOS 0.2.0 (48). Это дополнительный **серверный режим**, а не замена всех существующих профилей APL. На iOS Apple `NEPacketTunnelProvider` управляет маршрутизацией по IP; локальный exact-host direct egress внутри Packet Tunnel не является поддерживаемым способом согласно [Apple TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers). Для достижения первоначальной цели выбор маршрута перенесён на шлюз.

## Реализовано

- `free_gateway/smart.py`, `smart_server.py`: отдельный, аутентифицированный HTTP CONNECT шлюз; точное доменное имя из CONNECT проверяется по списку разрешённых пользователем. `site.test`, подтверждённые CSS/API/JS имена — **DIRECT с сервера**, неразрешённые домены, в том числе на том же IP, — **через исходный proxy**. У supplier credentials нет доступа с устройства. Direct до приватных IP запрещён, нет fallback между egress, все домены по умолчанию PROXY. Атомарный authenticated `PUT /v1/smart/policy`, TTL 180 с, клиентский refresh 60 с, 128 доменов максимум, входящий HTTP payload bounded. Server default localhost и требует TLS для внешнего bind.
- iOS `ProxyType.gateway = APL_GATEWAY`, новый тип в UI-пикере **APL Gateway (TLS)**. Перед подключением `PacketTunnelProvider` синхронизирует текущий ручной список плюс подтверждённые элементы Smart Graph, вместе с обязательными aliases (`gosuslugi.ru` → `www.gosuslugi.ru` и `gu-st.ru`) на шлюз через проверенный HTTPS, проверяет receipt. При неудаче не начинает VPN. В gateway-режиме клиент не создаёт site-IP-wide `/32`/`/128` и `--dns-bypass` для сайтов; исключает только адрес самого endpoint-шлюза. Прежние HTTP/HTTPS/SOCKS профили не меняются; изменения списка вызывают переподключение, refresh каждые 60 с.

## Реальное локальное сетевое доказательство

`tests/test_smart_gateway.py` поднимает **два настоящих TLS origin-сервера**, authenticated HTTP CONNECT gateway и отдельный HTTP CONNECT supplier. Клиент делает проверяемый TLS handshake с `site.test` / `api.site.test` / `static.site.test` / `tracker.other.test`, все hostname указывают на **один адрес 127.0.0.1**, но в результатах HTTPS разные независимые HTTP заголовки `X-APL-Egress: DIRECT` и `X-APL-Egress: SUPPLIER`. Три явно разрешённых домена идут DIRECT на origin A, tracker на том же IP — через supplier origin B. Без политик всё PROXY. Проверены неправильный клиентский токен (407), неверный policy token (401), wildcard rejection, отмена, TTL expiry и отказ upstream без direct leak. **Gateway + старый Free Gateway 17/17 PASS**.

**iOS:** 2 новых Core теста правильной выгрузки доменов, включая `gu-st.ru`, IPv4 literal не становится hostname. **115/115 Swift Core PASS**, **3/3 source contract PASS**, **iOS Simulator BUILD SUCCEEDED** с новым типом прокси и HTTPS policy sync.

## Отдельные незавершённые этапы

- Производственный Gateway **не установлен**: необходим выделенный публичный IP сервера (в предпочтительной географии — например, российский IP для сайтов, ограничивающих иностранный доступ), работающий и оплаченный исходный HTTP CONNECT proxy, DNS+TLS-сертификат, отдельные server credentials, мониторинг и защита доступа. Подключение на общий IP Tailscale Funnel/CDN опасно: сам endpoint VPN находится на общем IP и это вновь создаёт shared-IP egress. [Инструкция администратора](../free_gateway/SMART_GATEWAY.md).
- **Физический iPhone E2E не выполнен** (нужны развёрнутый Gateway и согласованный test-run с восстановлением существующего профиля). Не аттестованы UDP/QUIC, переключение Wi-Fi/LTE, производительность, многопользовательские квоты; существующие профили всё ещё имеют IP-wide semantic risk.
- DIRECT в новой схеме означает **с интернет-выхода Gateway**, а не с локального адреса телефона. Если требуется именно локальный IP iPhone без общего-IP риска, этот результат **не решает** задачу; потребуется платформенное решение или отдельный компромисс.

Код добавлен в Draft PR без App Store 0.1.41 Review/Apple upload, без изменения реальных iPhone/VPN/proxy, рекламы и privacy label. Следующая задача — `APL-SMART-GW-DEPLOY-001`: выделенный VPS + TLS + upstream credentials + физическая проверка двух egress и rollback.
