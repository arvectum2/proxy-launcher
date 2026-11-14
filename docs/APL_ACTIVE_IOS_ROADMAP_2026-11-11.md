# APL — активная дорожная карта: только iOS

**Решение владельца от 11.11.2026:** новая продуктовая разработка Arvectum Proxy Launcher сосредоточена исключительно на iOS. Остальные платформы и направления — PAUSED, история и существующие релизы сохранены. Более ранние записи в ROADMAP.md и LOCAL_EXECUTION_BACKLOG.md являются историческими срезами, если противоречат этому документу.

## Решение владельца 11.11.2026 — один объединённый iOS-релиз

**Следующий публичный выпуск планируется как один крупный кандидат 0.3.0**, вместо последовательности 0.2.1/0.2.2. [План интеграции и реальные технические gates](APL_IOS_030_UNIFIED_RELEASE_2026-11-11.md). Это цель разработки, не готовый IPA. Пункты ниже с заголовками «следующий релиз» изначально описывали узкую версию 0.2.1 и теперь являются составной частью одного кандидата; не публиковать промежуточную версию.

- [x] 11.11: HTTPS-подписки: прямая/ Base64 загрузка, сохранение ссылки с токеном в отдельном Keychain service, повторная загрузка вручную, безопасный предпросмотр/импорт; VLESS и другие неподдерживаемые строки отвергаются целиком.
- [x] 11.11: контракт и backend личной CloudKit базы для ручных исключений, preview/diff и предотвращение конфликтов; экран скомпилирован, но скрыт до entitlement/provisioning и физической приёмки.
- [x] 12.11: PR #358 VLESS/Reality source-only и PR #359 WG/AWG1 source-only merged по 17/17; `ProxyType` не расширен.
- [x] 12.11: [лабораторный симуляторный/линковочный gate Xray+WG](APL_IOS_030_UNIFIED_XRAY_WG_ENGINE_2026-11-12.md): один Xray outbound backend для VLESS и standard WG потенциально позволит избежать второго Go-runtime. Production original PacketTunnel egress не доказан.
- [x] 12.11: [офлайн-подготовка к приёмке](APL_IOS_030_DEVICE_ACCEPTANCE_HANDOFF_2026-11-12.md): безопасный SOCKS handoff builder и generation-aware fail-closed lifecycle, Apple SHA/Go dependencies provenance gate; нативный Swift Xray lab проверен на iOS Simulator без физического телефона. Новые протоколы **не включены** в App Store IPA.
- [x] 12.11: PR #361 и native DEBUG-only Rust/Xray lab завершены без iPhone. Canonical checkpoint `blocked`: ждём владельца с безопасным тестовым iPhone для реального egress, миграции Keychain и CloudKit; единственный целевой публичный релиз — 0.3.0.

- [ ] Автоматическое обновление подписки, CloudKit и новые сетевые протоколы: отдельные инженерные, entitlement/лицензионные и аппаратные gates, без ложного рекламирования.
- [ ] Публикация 0.3.0 после всех проверок, миграции и подписанной сборки.

---

## Публичные версии — разные каналы

- **macOS App Store 0.2.22 (18) — ВЫПУЩЕНА**, непосредственно подтверждено владельцем 11.11.2026. Публичная карточка Apple отдельно не проверялась. Исходники и QA: PR #310, merge 4e7b5808, подписанный build18, полный 3900-секундный физический PASS.
- **iOS App Store 0.2.0 (48)** — последний зафиксированный публичный продуктовый рубеж. Изменения следующей версии в main ещё не означают опубликованную сборку с QR.
- **GitHub/GitVerse desktop v0.2.16** — независимый комплект Windows/Linux/macOS DMG; выпуск macOS App Store 0.2.22 не создаёт тег desktop v0.2.22.
- **Android GitHub android-v0.1.38** — опубликован 07.10.2026. Статус RuStore требует отдельной проверки при возобновлении Android.

## P0 — iOS следующий релиз

- [x] iOS 0.2.0: адаптивный UI, 64 UI-языка, Auto/failover, Smart Routing 3.0; исходники, подпись и аппаратная приёмка зафиксированы.
- [x] После отправленной 0.2.0 в main объединены универсальный импорт ссылок/буфера/файлов/JSON, QR-передача профиля, Share Sheet, проверки безопасности размера/формата файлов и локализованные ошибки (PR #312, #320, #337, #340, #341).
- [x] Source-контракты, тесты и unsigned iOS ARM64 сборки новых изменений ранее проверены.
- [ ] Зафиксировать релизный состав следующей iOS-версии, конкретный исходный commit, инкремент build и бинарные проверки включения функций.
- [ ] Выполнить без потери пользовательских данных настоящий upgrade с опубликованной 0.1.41 на 0.2.0, включая Keychain, на отдельном тестовом iPhone. Симуляторная модель 8/8 PASS не заменяет физическую.
- [ ] Подписать и проверить новую iOS-сборку, принять отдельное решение о публикации.
- [ ] После первого QR-содержащего релиза провести QR iPhone→iPhone, системную камеру, Share, VoiceOver и безопасную передачу специальных символов — согласно ранее принятому решению владельца.
- [ ] При возможности заказать независимую редакторскую проверку локализаций носителями; технические 64/64 проверки не равны профессиональному QA.

## P0 — Smart Routing 4.0 (отдельный аппаратный gate)

- [x] Pure policy provenance и read-only объяснение DIRECT/PROXY, диагностическое сравнение со Smart3.
- [x] DEBUG original-flow trace, безопасный TTL 60 секунд от первого native события, однократные TCP witness, fail-closed (PR #343/#346/#350; 25/25 CI последнего).
- [ ] Доказать настоящий captured PacketTunnel flow и независимые одноразовые DIRECT/PROXY receipts на реальном iPhone.
- [ ] Отдельно проверить IPv4, IPv6, shared CDN-IP, UDP/QUIC, смену Wi-Fi/LTE и отзыв маршрута.
- [ ] До аппаратного PASS не расширять автоматически production DIRECT и не трактовать синтетический TCP как доказанный egress.

## P1 — iOS надёжность

- [ ] Держать native FIN/CLOSE_WAIT draft PR #314 отдельно от main до физического FIN, Safari upload/download, длительных соединений, Wi-Fi/LTE, failover и recovery PASS.
- [ ] Проверять сохранность Keychain/профилей и VPN recovery при обновлениях.
- [ ] Поддерживать iOS CI, контрактные и риск-ориентированные релизные проверки; не трогать рабочие коммерческие прокси или VPN без отдельного повода.

## P2 — будущие iOS-возможности, не считать выполненными

- [ ] iCloud/CloudKit синхронизация, отдельные privacy/entitlement gates.
- [ ] VLESS/Reality и по отдельному решению WireGuard/AmneziaWG.
- [ ] Подписки на прокси, пакетная выдача/обновление и расширенный UX поставщиков.

## Пауза других направлений

Windows WinDivert/new release, macOS per-app, Android/RuStore, Linux, Proxifier desktop, QRVPN Gateway, Marketplace, ГОСТ, международные трафик-квоты, реестр ПО и Роспатент **не являются активными направлениями**. Код, результаты, релизы, документы и исторический backlog остаются без удаления. Возобновление требует отдельного решения владельца.

**Следующий запуск:** читать .agent/current-task.yaml, этот индекс и нужные iOS QA-протоколы; не создавать новый Watchdog, не менять Scheduled Tasks, Apple/RuStore и не выпускать подписанный бинарник без отдельного релизного решения.

- [x] 12.11: Аппаратная baseline-проверка через iPhone Mirroring на iPhone 13 / iOS 27.2.1: APL 0.2.0, три профиля, пустые исключения, preview-only импорт, onboarding и язык; обнаружен и исправлен дефект подписей темы RU→EN. Simulator UI PASS, Python310+1513, Swift226, signed Debug iPhoneOS 0.3.0(49) PASS. См. [протокол](APL_IOS_030_IPHONE_MIRRORING_ACCEPTANCE_2026-11-12.md); установка новой версии и смена VPN закрыты до backup gate.

- [x] 12.11: подписанная Debug iOS 0.3.0(49) обновлена поверх 0.2.0 на физическом iPhone13 через Xcode CoreDevice без uninstall/reset/VPN. Три исходных профиля и выбранный UUID сохранились; два физических XCTests PASS (библиотека 14.077s, локаль RU→EN→RU 27.006s); App Group profiles.v1 до/после побайтно совпадают. Отдельный аппаратный XCTest безопасно пропускается на CI-симуляторе, Python312+1513/Swift226 PASS. [Протокол](APL_IOS_030_IPHONE_MIRRORING_ACCEPTANCE_2026-11-12.md). Keychain/VPN/VLESS/WG/CloudKit/App Store ещё не приняты.

- [x] 12.11: физический read-only XCTest в процессе подписанного Debug APL0.3.0(49) подтвердил 3/3 непустых сохранённых Keychain-пароля, код только чтение; App Group prefs до/после побайтно совпадают. Отдельная hardware QA Xcode-схема безопасно пропускает CI-симулятор. [Протокол](APL_IOS_030_IPHONE_KEYCHAIN_READONLY_2026-11-12.md). Реальный VPN-пакетный egress и публичный App Store релиз по-прежнему не приняты.

- [x] 12.11: физический iPhone13 подписанный Debug APL0.3.0(49): 3/3 авторизованных HTTP(S)/SOCKS5 CONNECT (производственный ProxyProbe), без системного VPN. App Group profiles.v1 и selected UUID побайтно неизменны. Протокол: APL_IOS_030_IPHONE_PROXY_HANDSHAKE_2026-11-12.md. Полный HTTPS egress, пакетный TUN, DNS/IPv4/IPv6/UDP, VLESS/WG и CloudKit ещё не приняты.

- [x] 12.11: физический iPhone13 Debug APL0.3.0(49) подтвердил полноценный HTTPS nonce receipt и отдельный egress IP через все 3/3 сохранённых прокси с Apple ProxyConfiguration.allowFailover=false, без системного VPN. Post-test App Group metadata точно совпадают. Протокол: APL_IOS_030_IPHONE_HTTPS_RECEIPT_2026-11-12.md. Реальная PacketTunnel/TUN маршрутизация, native VLESS/WG/Amnezia, CloudKit и публичный App Store остаются открыты.

- [x] 12.11: реальный PacketTunnel/TUN физический iPhone13/Debug APL0.3.0(49): preflight OFF, 20s/25s независимые kill switch, VPN Connected, два независимых HTTPS-сервиса подтвердили смену IP 2/2 и восстановление baseline после OFF 2/2. XCTest PASS 5.104s, отдельный signed read-only NetworkExtension OFF PASS, profiles.v1 и selected UUID неизменны. Протокол: APL_IOS_030_IPHONE_PACKETTUNNEL_EGRESS_2026-11-12.md. DNS/IPv6/UDP/Wi-Fi/LTE, VLESS/WG/AWG, CloudKit и публичный App Store ещё открыты.

- [x] 12.11: signed iPhone13 read-only direct IPv4/IPv6 baseline при APL VPN OFF: IPv6 api6 PASS, api4 неожиданно вернул IPv6, независимый ipv4.icanhazip.com IPv4 PASS. Оба семейства физически доступны, 3 исходных профиля и выбранный UUID неизменны. Следующий этап: IPv4/IPv6 через настоящий PacketTunnel. Протокол: APL_IOS_030_IPHONE_IPV4_IPV6_BASELINE_2026-11-12.md.

- [ ] 12.11: dual-stack PacketTunnel physical acceptance NOT PASS. IPv4-only + IPv6-only HTTPS domain requests time out -1001 with VPN ON, while numeric IPv4 Cloudflare HTTPS through PacketTunnel PASS with changed IP, and numeric IPv6 TLS -1200 is inconclusive. Per-session authenticated Apple proxy IPv4-only 3/3 PASS, IPv6-only 0/3. Physical DNS getaddrinfo returns correct synthetic 198.18/15 A in VPN for IPv4-only and dual-stack domains (no general resolver outage). Latest independent VPN OFF and profiles.v1/selected ID exact bytes intact. Details in APL_IOS_030_PACKETTUNNEL_DUALSTACK_DNS_DIAGNOSIS_2026-11-12.md. Next pinpoint fake IP→hostname→CONNECT→TLS in pinned Rust with nonsecret phase logs; do not patch product without source evidence.

- [x] 12.11: дополнительная source-only Debug CONNECT-трассировка без изменения маршрутов: реальный PacketTunnel на iPhone13 трижды подряд получил HTTP200 от IPv4-only тестового hostname и Rust CONNECT outcome code=0. До этого тот же hostname давал -1001, поэтому считать дефект исправленным преждевременно (возможно нестабильность сети/прокси/кэша). После каждого теста VPN OFF, профильные bytes и выбранный UUID по итогу неизменны. Протокол: APL_IOS_030_IPV4_ONLY_CONNECT_TRACE_2026-11-12.md. IPv6/UDP/Wi-Fi-LTE/DNS leak и публичный релиз по-прежнему не приняты.

- [!] 12.11: signed real iPhone13 read-only проверка альтернативных IPv6-only HTTPS endpoints при VPN OFF: v6.ident.me и ipv6.icanhazip.com оба напрямую PASS (валидный IPv6), но через 3 прежних аутентифицированных proxy — 0/3 каждый, как ранее api6.ipify.org 0/3. Для честной IPv6 PacketTunnel-приёмки нужен независимый тестовый прокси с подтверждённым IPv6 destination egress. Профили не меняли. Протокол: APL_IOS_030_IPV6_UPSTREAM_ALTERNATE_2026-11-12.md.

- [x] 13.11: iPhone13 signed Debug APL0.3.0 real PacketTunnel IPv6 QA через **одноразовый** ограниченный HTTP CONNECT proxy на Mac mini с native IPv6 egress, строго HTTPS/443 и public allowlist. v6.ident.me IPv6-only HTTPS через VPN PASS (iPhone IP заменён на адрес лабораторного прокси и восстановлен после OFF), XCTest 2.181s. Отдельно NWConnection к **числовому IPv6** Cloudflare с TLS SNI one.one.one.one/проверкой сертификата через тот же PacketTunnel HTTP200 PASS, CONNECT числового IPv6 подтверждён лабораторным сервером, XCTest 2.203s. Это доказывает исходный IPv6 packet TUN, не только VirtualDNS fake IPv4. Independent OFF, 3 owner profiles.v1 bytes and selected ID unchanged, temporary proxy terminated. Signed Debug, unsigned iPhoneOS Release, Python340+1513 and Swift226 PASS. Протокол APL_IOS_030_DISPOSABLE_IPV6_TUN_HARDWARE_2026-11-13.md. Коммерческие 3 прокси IPv6 upstream 0/3, приложение их не меняло; прочая приёмка и публичный релиз открыты.

- [x] 13.11: устранён source-level fail-open статуса iOS PacketTunnel при неожиданном завершении native tun2proxy (в том числе return code 0): `TunnelEngineExitGate` с generation token и остановкой NetworkExtension; штатный stop/switch инвалидирует предыдущую генерацию. Swift231/231, iOS Python343/343 +1513 PASS, unsigned iPhoneOS Release BUILD PASS. Физический fail-closed/UDP/DNS/Wi-Fi-LTE **ещё не принят**; подробности — [протокол](APL_IOS_030_ENGINE_UNEXPECTED_EXIT_FAILCLOSED_2026-11-13.md).
- [x] 13.11: отдельный source-only этап UDP leak-sentinel: одноразовый ограниченный IPv6 echo server, физический Debug XCTest с тремя явными opt-in переменными, две positive direct проверки, одноразовый UDP during VPN, OFF + восстановление, независимое подтверждение счётчика сервера. Это **не** DNS/QUIC/full UDP fail-closed acceptance; физическое выполнение ждёт отдельного разрешения. [Протокол](APL_IOS_030_UDP_NONLEAK_WITNESS_2026-11-13.md).
- [x] 13.11: encrypted standalone backup source/Files **export-only** lab: dedicated iOS27 simulator with synthetic Keychain profile and locally signed Debug app, real encrypted `.aplbackup` written by Files picker; verified 512-byte PBKDF2-SHA256/AES-GCM envelope, no synthetic secrets in plaintext; Swift 9/9 backup tests and Python340+1513 PASS. The system import picker opened empty **Recents**; full reimport remained **XCTSkip, NOT accepted**, next validate Browse and physical standalone export/restore separately. [Protocol](APL_IOS_030_ENCRYPTED_FILES_SIMULATOR_QA_2026-11-13.md).

- [x] 13.11 (день): устранена перезапись предыдущей `.aplbackup` при повторном экспорте (UTC timestamp + UUID в имени), импорт через File Provider ограничен максимум 1 МиБ + 1 байтом до выделения памяти под файл. Подтверждены два отдельных файла на одном чистом симуляторе, Swift230/230, Python343+1513, iPhoneOS Release build; полный Files Browse импорт всё ещё **не принят** и остаётся в следующих этапах. [Подробности](APL_IOS_030_ENCRYPTED_FILES_SIMULATOR_QA_2026-11-13.md).
- [x] 13.11: перед аппаратной проверкой DNS/UDP/QUIC/Wi-Fi/LTE устранена гонка старых таймеров `qaStopAfterSeconds` и `qaResetDirectAfterSeconds` при stop→start PacketTunnel: поколение QA-сеанса инвалидируется на остановке, callbacks выполняются только для текущего сеанса под атомарным lock. Swift232/232, Python344+1513, unsigned iPhoneOS Release+Debug QA builds PASS. Физическая радио/DNS/UDP/QUIC приёмка **не закрыта**. [Протокол](APL_IOS_030_QA_SESSION_TIMER_GENERATION_2026-11-13.md).

- [x] 13.11 интеграционная source-only ветка iOS0.3.0 (PR #377+#378+#379+#380 code cherry-picks без merge в main): PacketTunnel exit fail-closed + USB UDP leak witness + зашифрованные Files + поколение QA таймеров. Конфликты только в добавляемых строках дорожной карты, XcodeGen обновлён. Swift241/241, Python357+1527, unittest14/14, unsigned iPhoneOS Release+Debug QA builds PASS. **Это не подписанный релиз и не аппаратная приёмка.** [Протокол](APL_IOS_030_INTEGRATION_PREVIEW_2026-11-13.md).

- [x] 13.11 (вечер): iCloud manual exclusions source safety — перед применением удалённого снимка заново проверить private CKRecord (точный recordID/changeTag/содержимое) и локальные исключения; перед загрузкой в iCloud отправлять ровно предпросмотренный локальный список, запрещая upload после изменений. Swift244/244, Python361+1527. CloudKit feature flag и entitlement для пользователей по-прежнему **выключены**, физический двухустройственный конфликт и CAS на локальное применение не проверены. [Протокол](APL_IOS_030_CLOUDKIT_PREVIEW_CONSISTENCY_2026-11-13.md).

- [x] 13.11 (вечер): закрыт дополнительный source-level риск CloudKit upload: сравнение тип/ID ранее просмотренного CKRecord, декодированный snapshot, свежий remote snapshot и оба непустых changeTag; CAS на cloud write сохранён. Добавлено 6 изолированных Swift-сценариев двух условных устройств и конкурирующих cloud commits; Swift250/250 и Python362+1527. Это **не** реальная CloudKit двухустройственная приёмка; entitlement/production flag OFF. [Протокол](APL_IOS_030_CLOUDKIT_PREVIEW_CONSISTENCY_2026-11-13.md).

- [x] 14.11: ФИЗИЧЕСКИЙ READ-ONLY Mirroring: iPhone13 APL0.3.0(49), UI «Подключиться», 3 исходных профиля, системный Files-импорт «Недавние/Обзор/На iPhone» открывается. На реальном телефоне файлы не выбирали, копию не создавали, VPN/Keychain не изменяли. Синтетический Files UI QA **полный export→Browse→decrypt→idempotent restore на абсолютно новом iOS27 симуляторе 1/1 XCTest PASS, 0 skip, 0 failures**; в File Provider ровно одна новая 518-байтная `.aplbackup`, строка «Добавлено профилей: 0», Swift250/250, Python366+1527. Остаётся отдельный gate для резервной копии реальных данных пользователя. [Протокол](APL_IOS_030_FILES_BROWSE_PHYSICAL_READONLY_2026-11-14.md).

- [x] 14.11 (04:26–04:31 MSK) пользователь разрешил аппаратный DNS/UDP/QUIC/Wi-Fi-LTE QA. Сохранены защищённые App Group prefs, до/после попытки запусков Xcode prefs побайтно идентичны; подписанная iPhoneOS Debug QA сборка с 20с/25с safety guards успешно подготовлена (`build-for-testing`), entitlement/team сохранены. UDP witness на Mac mini локально 2/2, остановлен. **Физические XCTest заблокированы: Xcode требует прямой разблокировки iPhone**, Mirroring при физически заблокированном телефоне недостаточно. VPN не включали, реальные сетевые гейты НЕ приняты. [Протокол](APL_IOS_030_PHYSICAL_NETWORK_QA_2026-11-14.md).

- [x] 14.11 (09:20–09:27): физический iPhone13 разблокирован; signed NE OFF/Keychain3/3 до/после каждого активного теста; DNS VirtualDNS diagnosis PASS, локальный IPv6 UDP witness FAIL (4 вместо 3), runtime NE includeAll=false/excludeLocal=true/enforce=false; off-link USB RVI DNS53/QUIC443 — global-source count 1/0/1 и 5/0/6, 0 capture drops, real h3 handshake blocked under HTTP proxy and restored OFF. Wi-Fi→cellular→Wi-Fi interface-bound HTTPS PASS3/3 **при VPN OFF**, actual active handoff not accepted. Swift250, Python371+1527. Профили/выбор/организация побайтно по SHA совпадают, VPN OFF, временный стенд остановлен. Остались strict-LAN policy decision, independent off-link generic UDP witness, actual active radio handoff. [Протокол](APL_IOS_030_PHYSICAL_NETWORK_QA_2026-11-14.md).

- [x] 14.11 (09:29–09:31): независимый внешний UDP sentinel STUN/3478 на реальном iPhone13 с random transaction ID, valid reply до/после VPN, no reply в активном HTTP-туннеле, USB RVI global-source count 1/0/1, 3 packets/0 drops, signed XCTest PASS5.322s. NE OFF/Keychain3/3/profile parity до/после PASS. Это bounded off-link non-DNS/QUIC UDP evidence; не independent server-count echo и не отказ локальной сети. Python372+1527, RVI unittest6/6, signed build PASS. [Протокол](APL_IOS_030_PHYSICAL_NETWORK_QA_2026-11-14.md).

- [x] 14.11 09:59–10:01: физический fail-closed при реальной остановке disposable HTTP proxy: initial XCTest PASS, RVI 9/0/0 INCONCLUSIVE; после 2s settle/расширения только контрольных окон повторный signed XCTest PASS13.960s, independent host relay-exit receipt, RVI TCP/443 global 11/0/11, 39 packets/0 drops. TLS true/false/true; pre/post NE OFF & Keychain3/3 & profile parity PASS. Python373+1527, RVI unittest7. Production routes unchanged; active radio handoff still pending. [Протокол](APL_IOS_030_PHYSICAL_NETWORK_QA_2026-11-14.md).

- [x] 14.11: нативный VLESS/REALITY config gate: pinned libXray26.11.9 converter response → typed candidate consistency/strict allowlisted one VLESS RAW outbound → local SOCKS5 (без DIRECT, UDP, persistence). Реально запущенный свежий ARM64 iOS27 Simulator: 2/2 PASS convert/test/run/SOCKS greeting/stop, отдельно с Vision и без; Swift255/255, Python373+1527, unsigned iPhoneOS Release build PASS, без LibXray symbols/assets. **Настоящий peer handshake, PacketTunnel original-flow и физическая приёмка не пройдены.** [Протокол](APL_IOS_030_XRAY_PACKETTUNNEL_LAB_2026-11-12.md).

- [x] 14.11: реальный изолированный VLESS/REALITY peer: pinned libXray26.11.9 macOS server + ARM64 iOS27 Simulator client, ephemeral keys, separate loopback HTTP nonce witness; with/without Vision 2/2 exact data responses, bad UUID/bad REALITY key/peer stopped 3/3 denied, independent witness counts 1/1/0/0/0. Full fresh single-command `--peer` reproduction PASS5/5, cleanup PASS; no production linkage or physical phone change. Actual original-flow PacketTunnel handoff, hardware, WireGuard/AWG and legal gates pending. [Протокол](APL_IOS_030_XRAY_PACKETTUNNEL_LAB_2026-11-12.md).

- [x] 14.11: actual synthetic original IPv4/TCP packets on private Darwin-framed socketpair -> native Rust tun2proxy -> Xray SOCKS/VLESS/REALITY -> independent local witness; real 5/5 with/without Vision, bad UUID/key and stopped server, counts 1/1/0/0/0; 5/5 Rust exit0/drain/caller descriptor closed/Xray stopped. Fresh --tun one-command reproduction PASS, cleanup verified. Simulator peak RSS 61–66 MiB, not actual physical extension footprint. Next signed isolated NE packet-flow QA and same-process resource/restart tests, then physical acceptance. [Протокол](APL_IOS_030_XRAY_PACKETTUNNEL_LAB_2026-11-12.md).

- [x] 14.11: same-process VLESS/TUN lifecycle: older Rust archive 6/6 short run, longer run exit255 after 2–3; forced-exit literal present in both unstamped old slices. Rebuilt pinned source/toolchain/patches in separate directory, no literal, manifest/digests verified, guard rejects both stale artifacts. New archive fresh 12/12 same-process real packet receipts, stable FD12 after warmup and10 after settle (INET0), RSS peak63.5MiB/final60.4MiB. Fresh --tun negative/positive regression5/5. Isolated unsigned ARM64 NE provider build+native linkage PASS with rebuilt archive; no matching separate lab provisioning, no signing/install/device change. Only active QA symlink updated; main/shared artifact unchanged. Next actual signed isolated NE and hardware resource/exit QA, then native WG/AWG and legal gates. [Протокол](APL_IOS_030_XRAY_PACKETTUNNEL_LAB_2026-11-12.md).

- [x] 14.11: стандартный WireGuard через Rust synthetic original TCP -> Xray native WG outbound -> independent loopback UDP header witness -> separate macOS native WG inbound -> nonce HTTP receipt. Fresh --wg runner PASS4/4, valid init/reply1/1 transport4/3 and exact count1; wrong server key/PSK/stopped peer count0/0/0; all exit0/drain/FD close/stop. No production or phone changes. Actual NE, independent WG implementation, IPv6/app UDP, AWG provenance and transport remain. [Протокол](APL_IOS_030_WIREGUARD_RESEARCH_2026-11-12.md).

- [x] 14.11: isolated AmneziaWG official v3.1.20260828 pinned source b5928efb6, verified Go1.25.0 tar and dependency hashes; separate AWG-only macOS/iOS-sim/iPhoneOS native static archive + link PASS. Fresh one-command native macOS + iOS27 Simulator each PASS3/3 (bidirectional exact IPv4/IPv6 ICMP, wrong public key and PSK negative with actual loopback UDP send/receive and no receipt, socket close). 23 focused checks. Legacy fixed synthetic fixture on v3 engine, not all AWG versions, nor OS NE/real phone. Preliminary MIT/BSD dependency inventory. Separate AWG process chosen; no production linking. [Протокол](APL_IOS_030_AMNEZIAWG_NATIVE_LAB_2026-11-14.md).

- [x] 14.11: standard WG independent non-Xray interoperability: official wireguard-go pinned f333402bd9, standalone userspace netstack macOS peer; corrected Rust + pinned Xray iOS27 simulator original synthetic TCP -> real WG UDP -> exact independent HTTP witness. --wg-reference fresh run PASS4/4 (valid receipt1, wrong key/PSK/stopped0/0/0), valid init/reply1/1 data6/5, all drain/stop and cleanup. 26 focused tests PASS. Actual NE, app UDP/IPv6 and physical acceptance remain. [Протокол](APL_IOS_030_WIREGUARD_REFERENCE_INTEROP_2026-11-14.md).

- [x] 14.11: standard WG dual-stack application packets through official independent reference peer. Old Rust reproducibly failed UDP4/UDP6 with Darwin EISCONN56 (connected UDP socket + sendto); corrected pinned source to use one connected send/recv datagram, both device/sim source builds and manifest/digests verified. Fresh --wg-dual PASS12/12 (valid UDP4/UDP6/TCP6 exact1/1/1; bad key/PSK/stopped0/0/0 each, all native drain/stop; valid handshake3/3 data7/7, negative no transport data). 31 focused checks. No OS NE/phone/production activation or general leak claim; MTU/QUIC/DNS, backend isolation, actual signed NE and hardware still pending. [Протокол](APL_IOS_030_WG_UDP_IPV6_LAB_2026-11-14.md).
