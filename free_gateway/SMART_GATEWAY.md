# APL Smart Gateway — настройка доменных исключений с серверным выходом

Это **отдельный сервис** и опциональный тип iOS-профиля `APL Gateway (TLS)`. Потребуются сервер с **собственным выделенным публичным IP**, действующим TLS-сертификатом и HTTP CONNECT upstream proxy. Разрешённые сайты видят **IP сервера Gateway**, а не локальный IP iPhone. Остальные домены идут через серверный исходный прокси, его пароль никогда не передаётся клиенту. Все существующие профили APL остаются как были.

Схема: iPhone → HTTPS CONNECT Gateway → exact разрешённый host с подтверждёнными CSS/JS/API ресурсами DIRECT с сервера. Любые остальные имена, включая чужие сайты с тем же DNS IP, идут через поставщика прокси. У HTTPS CONNECT совпадения *по IP* не дают разрешение: только точное имя и авторизованная политика. DIRECT действует для TCP 80/443, остальные порты уходят через исходный прокси. Недоступность DIRECT или upstream никогда не вызывает скрытого переключения на другой маршрут.

При VPN Connect приложение синхронизирует домены с `PUT /v1/smart/policy` по **проверяемому HTTPS**, Basic-auth (отдельный пользовательский токен, сохранённый в iOS Keychain), сверяет количество доменов и лишь затем запускает VPN. Сервер хранит список **180 секунд**, iOS обновляет каждые **60 секунд**. При обновлении исключений APL переподключает VPN и атомарно заменяет server policy. Если повторная синхронизация не удалась, gateway-proxy режим fail-closed (спустя TTL всё идёт через поставщика прокси).

## Переменные окружения на сервере

Хранить в приватном `.env`, не коммитить. Все примеры ниже — **заглушки**.

```bash
APL_GATEWAY_TOKEN_SECRET=<server-side-64-char-random-secret>
APL_FREE_PROXIES_JSON='[{"id":"upstream1","label":"Supplier","country_code":"US","host":"PROXY_HOST","port":8000,"username":"SUPPLIER_LOGIN","password":"SUPPLIER_PASSWORD","tls":false}]'
APL_SMART_GATEWAY_ACCOUNTS_JSON='[{"username":"apl-client-1","token_sha256":"<sha256-of-unique-client-token>","upstream_id":"upstream1"}]'
APL_SMART_GATEWAY_BIND=0.0.0.0
APL_SMART_GATEWAY_PORT=443
APL_SMART_GATEWAY_TLS_CERT=/etc/letsencrypt/live/gateway.example.com/fullchain.pem
APL_SMART_GATEWAY_TLS_KEY=/etc/letsencrypt/live/gateway.example.com/privkey.pem
```

Два **разных** секрета через `openssl rand -hex 32`, хеш клиента: `printf '%s' "$CLIENT_TOKEN" | shasum -a 256`. Запуск: `python3 -m free_gateway.smart_server` из каталога репозитория с загруженными переменными. Приложению выдаётся **только** `gateway.example.com:443`, username `apl-client-1` и клиентский токен. Логин и токен в iOS профиле. Внешний listener **не стартует без TLS**. Для привязки 443 используйте systemd socket privileges или другой защищённый способ вместо запуска всего процесса от root. Нужен firewall, ограничение частоты/квот и наблюдение за сертификатами; сервис не проходил полный production security audit.

**Нельзя использовать общий публичный IP Tailscale Funnel/CDN** для Gateway: его IP может обслуживать посторонние сайты и тогда прямое исключение для самого gateway peer создаст риск shared-IP egress уже на iPhone. Внутренний `tailscale serve` тоже не универсален, поскольку два iOS VPN-клиента нельзя считать независимыми одновременно. Нужен выделенный публичный адрес и валидный TLS сертификат шлюза.

## Подтверждённые проверки / ограничения

`uv run --with pytest pytest -q tests/test_smart_gateway.py tests/test_free_gateway.py` — реальный HTTPS CONNECT на двух TLS origin-серверах (DIRECT/SUPPLIER), авторизация, отзыв исключений, 180-секундный TTL и отказ без альтернативного egress; старый Free Gateway не изменил поведение. `cd mobile/ios && swift test`: тесты доменных правил/Graph и профилей. Симуляторная сборка iOS прошла.

**Не выполнено:** развертывание на публичном сервере, подключение настоящего исходного прокси, тесты *физического iPhone*, UDP/QUIC, переезд между Wi-Fi/LTE, надёжность публичной службы, rate limits, ротация секретов и Apple Review. Старые не-gateway профили всё ещё используют прежние IP-wide исключения и сохраняют прежний shared-IP risk. Новый режим не активируется автоматически.
