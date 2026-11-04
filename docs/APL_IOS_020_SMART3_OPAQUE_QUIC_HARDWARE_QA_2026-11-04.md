# APL iOS 0.2.0 — аппаратная маршрутизация QUIC, raw IP и DoH endpoint

Дата: 03.11.2026 22:44–23:58 МСК; окончательные проверки 04.11.2026.
Аппарат: iPhone 13, iOS 27.2, APL 0.2.0 (48).
Ветка: feat/ios-020-smart3-exact-flow-direct-20261103.

App Store Connect upload, merge и публикация не проводились.

## Два независимых аппаратных прогона

Первый: 03.11, 22:44. Временный HTTP CONNECT mock на частном LAN адресе
192.168.1.80:18081, auto-shutdown за 115 секунд, без пересылки наружу.
Только DEBUG ephemeral tunnel, никаких реальных платных прокси или профилей.

- Два разных исходных TLS TCP-соединения к www.apple.com восстановились
  после двух отказов proxy CONNECT. Новый TLS-поток получил ответ по DIRECT IPv4.
- Raw-IP 23.12.156.37:443 (общий CDN IP в предыдущем A/B) НЕ унаследовал
  разрешение по доменному имени: один реальный CONNECT через upstream mock.
- dns.google:443, hostname сервера DoH, тоже использовал upstream mock:
  один реальный CONNECT. Дешифрование DoH и реальный DoH-запрос
  намеренно не выполнялись.
- Отправленный обычный UDP/443 пакет на этом этапе НЕ был полноценным
  подтверждением QUIC и таковым не засчитывается.
- Фактический NWPathMonitor зафиксировал network changed и маршрут DIRECT
  был отозван. Точный радиопереход Wi-Fi ↔ LTE не подтверждён.

Второй: 03.11, 23:56. Вместо обычной UDP-посылки — реальный
Network.framework NWProtocolQUIC.Options(alpn: ["h3"]), запуск QUIC-попытки
для разрешённого TCP host www.apple.com.

- Система инициировала QUIC/h3, а pinned Rust engine дважды зафиксировал
  событие 12 в UDP/proxy ветке для того же одобренного TCP-host.
  В этой ветке нет вызова физического DIRECT.
- Два первоначальных TLS-потока получили ответы; ещё один новый поток
  получил TLS-ответ. Три физических DIRECT IPv4, НОЛЬ физических DIRECT IPv6.
- Независимый mock подтвердил два target CONNECT timeout, один здоровый
  upstream CONNECT, один raw-IP CONNECT и один DoH endpoint CONNECT.
- Из-за ограничения TelemetryStore до 40 последних событий ранняя отметка
  direct armed вытеснилась из кольца. Независимый анализ не подменяет её
  предположением: требует 2 исходных same-flow recovery, 2 TLS ответа,
  >=2 событий payload от Rust, >=3 scoped IPv4 TCP sockets,
  факт QUIC start и событие Rust UDP/proxy event12.
- Итог скрипта scripts/qa_smart3_physical_evidence.py с --opaque-quic:
  REAL_QUIC_ENGINE_UDP_PROXY_FAILCLOSED_DEVICE_PASS
  raw_ip_upstream_connects=1,
  doh_endpoint_upstream_connects=1,
  original_tls_responses=2,
  fresh_tls_responses=1,
  quic_network_framework_starts=1,
  quic_packets_observed_by_udp_engine=2,
  direct_ipv4_sockets=3, direct_ipv6_sockets=0.
- Лог mock: /private/tmp/apl-smart3-real-quic-mock-20261103.log.
  Закрытая копия telemetry:
  /Users/master/Library/Application Support/Arvectum/ios-020-smart3-quic-qa-20261103/after-group.plist.

Не утверждается успешное соединение QUIC/h3: тестовый HTTP-прокси
НАМЕРЕННО не поддерживает UDP relay. ECH не расшифровывался, DoH payload
не инспектировался. Проверено именно fail-closed и изоляция exact-host
DIRECT от UDP и неизвестного TCP destination.

После КАЖДОГО испытания восстановлены все prefs: App Group 11/11,
app 19/19, SHA-256 per value без несовпадений. iPhone вновь работает
на Release-компиляции 0.2.0 (48), подписанной для локального теста
Apple Development и с включёнными живыми баннером и native РСЯ.
App Store Distribution IPA на iPhone не устанавливается напрямую.

## Код / защита

Rust в UDP ветке продолжает использовать upstream proxy; для наблюдения
добавлено событие 12, только после физического exact-host TCP approval.
В Swift ограниченное логирование 2 событий; никаких данных пользовательских
пакетов не сохраняется. Отдельный source guard в tests проверяет связь
event12 с UDP handler, а не с TCP DIRECT.

- Rust pinned 0.8.3: 13/13 PASS, патч final library полностью replayable
  поверх предыдущих source-pinned изменений.
- Swift iPhone DEBUG build-for-testing: BUILD SUCCEEDED.
- Python iOS: 173/173 + 73 subtests PASS, включая отрицательные oracle тесты.
- Более ранние Swift Core 132/132 PASS, Simulator 9/9 PASS не менялись
  после этого изменения.
- Рекламный код/боевые ID и privacy metadata не менялись.

## Актуальный подписанный Release RC

- Архив: /private/tmp/APL-iOS-020-Smart3-QUICSafe-AdsFinal-20261103.xcarchive
- IPA: /private/tmp/APL-iOS-020-Smart3-QUICSafe-AdsFinal-20261103-export/Arvectum Proxy Launcher.ipa
- Размер IPA: 9 060 185 bytes.
- SHA-256: d8f2442c51ebd9e1f960d212d673890135a458f8ff3e2f8e6c686789cdffe4d3
- ARCHIVE/EXPORT PASS, ZIP/PACKET TUNNEL/APP code signatures PASS.
- Проверка mandatory production RSYA ads --ipa PASS; в бинарном архиве
  YandexMobileAds, 228 SKAdNetworkItems и рабочий PacketTunnel.
- Этот IPA заменяет ВСЕ предыдущие локальные артефакты 0.2.0 (48).

## Открытые условия полного готового продукта

1. Настоящий контролируемый Wi-Fi→LTE→Wi-Fi radio handoff при активном
   DIRECT не проверен. Путь NWPathMonitor уже привёл к автоотзыву, а
   симуляция этого callback и короткий TTL были проверены отдельно.
2. На IPv6-only сайте физический bounded TCP ранее устанавливался, но
   TLS payload зависал. Текущая реализация правильно FAIL CLOSED:
   прямой выход допускается только при публичном IPv4. Для AAAA-only
   применяется исходный PROXY. Полноценный IPv6-only DIRECT не готов.
3. Apple App Review, а не предварительный DTS, решит допустимость при
   последующей подаче. Ни принятия Apple, ни актуальной отправки не было.

См. также:
- APL_IOS_020_SMART3_FINAL_DEVICE_QA_2026-11-03.md
- APL_IOS_020_RSYA_DEVICE_AND_RELEASE_QA_2026-11-03.md
