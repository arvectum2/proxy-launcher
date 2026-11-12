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
