## 01.11.2026 — APL iOS 0.2: крупный релиз после 0.1.41

**Решение владельца:** заметно расширить продукт в 0.2, сохранив рекламу РСЯ и **главную кнопку подключения внутри приложения** как основной пользовательский сценарий. Не добавлять новые виджеты/Control Center one-tap connect: они сокращают открытия приложения и потенциальные рекламные показы. Существующие Shortcuts не ломать, но не выводить на первый план. Не требовать просмотра рекламы ради подключения. [Спецификация](APL_IOS_020_RELEASE_SCOPE_2026-11-01.md). **0.2 ещё не опубликована.**

- **P0 Импорт:** [x] `ip:порт:логин:пароль`, TXT/CSV/XML, URL/QR, предпросмотр и дубликаты (PR #295, main); [ ] регрессия на iPhone с обновлением 0.1.41 → 0.2.
- **P0 Организация профилей:** [x] поиск, избранное, собственные группы, фильтр, мультивыбор/массовое удаление с подтверждением и управлением ошибками Keychain в отдельной ветке; [x] хранение метаданных отдельно от прежних профилей, модульные тесты; [ ] физическая проверка сохранности Keychain и сценариев массового удаления.
- **P0 Скорость и трафик:** [x] уже существуют `scanProfiles`/`ProxyProbe`; [x] добавлены максимум 3 автоматических проверки / пакет до 10 ручных, cooldown 180/10 сек., отображение задержки, защита от параллельного сканирования, тесты политики; [ ] физически проверить трафик на тарифном прокси.
- **P0 Автовыбор и восстановление:** [x] `FailoverPolicy` (cooldown, порог, подавление недоступных серверов, возврат к приоритетному); [x] резервные серверы ранжируются по локальным замерам задержки до 10 минут, без изменения выбора приоритетного/последнего успешного; [ ] аппаратные тесты отказа/восстановления и давления соединений.
- **P0 UX/реклама:** [x] Home, onboarding, темы/языки, нижний баннер уже есть; [ ] улучшения интерфейса/локализаций, реальная проверка рекламы на iPhone, доступность и диагностика ошибок.
- **P1, после прототипа:** Smart Exclusions на iOS, безопасный экспорт/резервное копирование, IP/DNS-диагностика.
- **Не включать:** новый виджет подключения, VLESS+REALITY, маркетплейс прокси, облачную синхронизацию.
- **QA 01.11:** 80/80 Swift Core PASS, ARM64 iOS Simulator Debug build PASS, 12/12 сфокусированных Python-контрактов PASS. Старые 155-ключевые каталоги сохранены, строки 0.2 вынесены в `ProfileManagement.strings` (RU/EN и EN fallback). Новый UI-тест нашёл отсутствующий accessibility ID строки — исправлен, повторный прогон ожидается; физический iPhone сейчас недоступен. PR #296 — Draft, не релиз.
- **Приёмка:** целевые unit/UI тесты и сборка, отсутствие потери профилей/секретов/исключений при обновлении, физический iPhone, рекламный smoke, TestFlight, затем отдельное решение об App Review. Приватность в карточке Apple не менять без отдельного анализа.

## 01.11.2026 — iOS 0.1.42: универсальный импорт файлов поставщиков

- [x] Добавлен приём `IP:порт:логин:пароль` прямо из текста и массового TXT, CSV (с заголовками или без, запятая/точка с запятой/табуляция), а также структурированного XML; прежние HTTP/HTTPS/SOCKS5 URL/QR сохранены.
- [x] Выбор HTTP/HTTPS/SOCKS5 по умолчанию для строк без протокола, предпросмотр и фильтр дубликатов без отображения паролей; отклонение некорректной партии целиком, лимиты 200 записей / 256 KB, локальный XML без DTD/сущностей.
- [ ] После зелёного CI и проверки App Review 0.1.41 подготовить отдельный релиз 0.1.42. Поддержка остальных приложений APL и нестандартных XML-схем поставщиков — отдельный объём. [Подробности](APL_IOS_042_BULK_PROXY_IMPORT_2026-11-01.md).

## 31.10.2026 — iOS 0.1.42: пользовательские сценарии и релизная готовность

- [x] По авторизованному Apple API версия 0.1.41 (46) и отправленная заявка — **WAITING_FOR_REVIEW**; Apple Connect не изменяли.
- [x] Прямой импорт ссылки/QR в onboarding; локализованный импорт (6 приоритетных языков и English fallback), объяснение дубликатов, защита от пустого буфера, безопасное закрытие камеры.
- [x] Кнопки профилей адаптированы под длинные подписи; локальные тесты интерфейса RU/EN и перехода из инструкции проходят, simulator build PASS.
- [x] **Реальное оптическое QR-сканирование PASS:** пользователь навёл iPhone на QR с другого дисплея, ассистент независимо подтвердил по снимку `APL QR check`, HTTP, `qr-check.invalid:8080`, предпросмотр (1); фиктивный профиль не сохранён. Исправлена косметическая группировка цифр порта в SwiftUI. [Отчёт](APL_IOS_042_PRODUCT_READINESS_2026-10-31.md).
- [ ] После исхода Apple Review 0.1.41 подготовить отдельный Release IPA 0.1.42 (47) и отправить только после отдельного релизного решения.

## 31.10.2026 — iOS: аппаратная аттестация внешнего IP (0.1.42)

- [x] Два независимых HTTPS-источника подтверждают **смену публичного IP 2/2** при подключённом APL VPN и восстановление **2/2** после отключения (второй read-only замер после короткого периода перестроения маршрутов). Строгий физический XCUITest PASS; отдельный postflight подтверждает OFF, профили сохранены, телефон доступен.
- [x] Проверка устойчивости baseline перед VPN, а также отсутствие публичных IP и паролей в логах; тест изолирован от обычного CI флагом `APL_RUN_EXPLICIT_VPN_QA`.
- [ ] Агрегированные счётчики трафика внутри `PacketTunnel` и точное подтверждение выбранного upstream-прокси; восстановление сторонних VPN; оптический QR выполнен отдельно 31.10.2026. [Аппаратный отчёт](APL_IOS_042_PUBLIC_EGRESS_ACCEPTANCE_2026-10-31.md).

## 31.10.2026 — iOS 0.1.42: разрешённый живой VPN smoke на iPhone

- [x] Подписанная DEBUG-сборка и три аппаратных XCUITest: APL VPN до теста **OFF**, кратковременное соединение реально достигло **ON**, внешний HTTPS через отдельный test runner — **HTTP 200**, штатное отключение и повторная независимая проверка **OFF**. Все 3 теста PASS, телефон доступен, профили сохранены.
- [x] Предусмотрены независимые DEBUG-only автоматические отключения через 20/25 секунд, но в успешном тесте они не понадобились.
- [ ] Расширенная проверка: внешний IP/счётчики фактически проксированных байтов (нельзя делать вывод о конкретном proxy egress только по HTTPS 200); состояние другого VPN после временного переключения; оптический QR подтверждён отдельно 31.10.2026. [Отчёт](APL_IOS_042_LIVE_VPN_SMOKE_2026-10-31.md).

## 31.10.2026 — iOS 0.1.42: продолжение аппаратной приёмки

- [x] Smart Exclusions: **8 → 0 замечаний** штатного физического accessibility-аудита; поддержка Dynamic Type и контраст исправлены без удаления основных предупреждений.
- [x] Два аппаратных теста распознавания QR через Core Image + Vision и передачу результата в production `ProxyImport` (валидный SOCKS5/некорректный VLESS); AVFoundation камера отдельно уже проверена.
- [x] Защищённый DEBUG-only opt-in сценарий реального VPN со страховочными отключениями через 20/25 секунд, но **сам туннель не включался** из-за возможного конфликта с другими VPN на iPhone.
- [ ] Оптический QR и краткий live VPN smoke выполнены 31.10.2026; остаётся ручной VoiceOver остальных экранов. [Подробности](APL_IOS_042_A11Y_QR_VPN_FOLLOWUP_20261031.md).

## 31.10.2026 — iOS next candidate 0.1.42 (47): correct debug/build identity

- [x] Проверено, что `0.1.41 (46)` — отдельный подписанный архив, уже отправленный в Apple App Review 30.10.2026; его файл и анкеты App Store Connect не менялись. Исходный `main` после PR #286 содержит больше новых функций, но ошибочно оставлял `0.1.40 (45)` в Xcode-проекте.
- [x] Следующая **тестовая** сборка на базе актуального `main` помечена `0.1.42 (47)`; в `project.yml` и сгенерированном проекте Xcode версия согласована; подписанная Debug-сборка установлена и запущена на iPhone 13 без удаления пользовательских данных, номер `0.1.42` виден в интерфейсе.
- [x] Повторный запрос iOS XCTest автоматизации сработал: на **0.1.42 (47)** полный физический прогон **23/23 PASS**, включая реальную камеру QR (без оптического распознавания), WebKit, EN/HE, Smart Exclusions, Network.framework и accessibility (8 оставшихся замечаний).
- [ ] `0.1.42 (47)` **НЕ** загружена в Apple и не отправлена на проверку. Единая приёмка всех сценариев (рабочий VPN/оптический QR/VoiceOver) и решение о релизе — отдельный этап после подтверждения состояния `0.1.41` в Apple.

## 31.10.2026 — iOS: приёмка на физическом iPhone 13

- [x] Спаренный по Wi‑Fi iPhone 13/iOS 27.2: подписанная тестовая сборка, 6 UI-тестов импорта/QR-камеры/EN+HE/Shortcuts, 9 реальных тестов Network.framework, 5 Smart Exclusions и 1 read-only VPN status — **21/21 успешная проверка** после исправления диагностики DNS/TLS и устранения нестабильного ожидания WebKit.
- [x] Отдельный Xcode accessibility-аудит: выявлено 15 проблем, часть UX/контраста/крупного текста исправлена; на симуляторе после правок — 7 оставшихся замечаний (по состоянию 31.10.2026). Полный VoiceOver-приёмочный gate не закрыт.
- [ ] После последних UX-изменений повторить XCUITest на iPhone, когда сервис iOS снова позволит `enable automation mode` (сейчас Xcode timeout). Проверить живой VPN через разрешённый прокси и оптическое QR-считывание с другого экрана, сохранив состояние устройства.
- [ ] Реальный per-domain bypass, коммерческое получение подписок/оплата и полная WCAG/VoiceOver приёмка не включены в этот источник изменений. [Аппаратный отчёт](APL_IOS_PHYSICAL_ACCEPTANCE_2026-10-31.md).

## 31.10.2026 — iOS Marketplace: технический контракт без продаж

- [x] Подписанная Ed25519 модель управляемого манифеста: HTTPS-источник, issuer/ключ, 32 профиля, TTL, revision, строгие поля и запрет тихой смены сервера/транспорта.
- [x] Подготовлены API-контуры будущего backend, Keychain и политика отката на последнюю действительную подписку. Проверка модели без сетевого обращения и денег.
- [ ] Реальный HTTP client, подписанные доверенные ключи, StoreKit/рублёвая оплата, серверы, право на услугу и обработка ПД — после конкретного решения владельца и проверки Apple 3.1/5.4 и применимого права РФ. [Проект](APL_IOS_MANAGED_MARKETPLACE_ARCH_2026-10-31.md).
- [ ] Общая аппаратная приёмка обновлённой iOS версии, включая managed profile, только после подключения реально разрешённого сервиса.

## 31.10.2026 — iOS Shortcuts: ручные быстрые действия VPN

- [x] Три новые App Intents: «Подключить APL», «Отключить APL», «Переключить APL» (iOS 16+), защищённые от двойных вызовов/состояния disconnecting; прежняя автоматизация по приложениям сохранена.
- [x] Отдельные переводы названий команд на 16 языков, раздел справки в настройках, переход в «Команды», 50×155 старых переводов сохранены.
- [x] Swift unit, Python source contracts, сборка симулятора и экран помощи проверены; [документ](APL_IOS_QUICK_ACTIONS_2026-10-31.md).
- [ ] Реальное исполнение App Intents/Shortcuts и VoiceOver на обновлённой версии iPhone. Control Center/WidgetKit — отдельный этап, не считать выполненным.

## 31.10.2026 — iOS UX/локализация Smart Exclusions 2.0

- [x] Исправлено ручное переключение языка для кнопок настроек, добавлена безопасная английская fallback-редакция новых сообщений.
- [x] Основные действия/статусы Smart Exclusions переведены на 14 приоритетных языков, включая `ar`, `fa`, `he`; 50 исходных каталогов по 155 ключей без изменений.
- [x] Увеличены области нажатия и добавлены уникальные accessibility labels для опасных действий; iOS Simulator UI-проверки EN и HE/RTL PASS.
- [ ] Длинные тексты на 36 языках используют EN fallback; полноценная редактура и физический VoiceOver/увеличенный шрифт входят в общую приёмку обновлённой версии. [Детали](APL_IOS_SMART2_UX_LOCALIZATION_2026-10-31.md).

## 31.10.2026 — Smart Exclusions 2.0 (исходники и симулятор; iPhone позже)

- [x] Локальный граф связанных доменов с доказательствами, TTL семь дней и явным согласием, индивидуальным удалением, Undo и совместимой миграцией старых правил.
- [x] Сторонние HTTPS/CDN видимы как подсказки, но не добавляются автоматически. Сохраняется предупреждение об общих IP.
- [x] Тесты Swift/Python и симулятора; ограничения и план динамического per-flow движка в [техническом документе](APL_IOS_SMART_EXCLUSIONS_2_2026-10-31.md).
- [ ] Phase C: pure Swift policy prototype тестируется; настоящий per-domain/per-flow bypass, аппаратные проверки shared IP, IPv6/QUIC и полной загрузки сайтов.
- [ ] Совместная приёмка на следующей новой iOS версии, без изменений текущей заявки Apple.

## 31.10.2026 — iOS P1: типизированная диагностика недоступности профилей (source QA)

- [x] Выведены безопасные, локально отображаемые причины NET/DNS/TCP/TLS/AUTH/HTTP 407/PROXY/TIMEOUT/PROTOCOL/VPN; UI не отображает исходный текст системной ошибки, адрес/логин/пароль профиля в диагностическом коде.
- [x] HTTP CONNECT 407 (включая Digest challenge) больше не принимается за успешный CONNECT; неверные методы SOCKS5 отклоняются.
- [x] Сетевые callback защищены однократным завершением и таймаутом; асинхронный мониторинг профилей — от устаревших результатов.
- [x] 38 Swift core tests, 1086 Python unittest (1 skipped), 3/3 iOS Simulator UI, Debug build — PASS. Техническое описание: [APL_IOS_CONNECTION_DIAGNOSTICS_2026-10-31.md](APL_IOS_CONNECTION_DIAGNOSTICS_2026-10-31.md).
- [ ] Протестировать физические сценарии DNS/TCP/HTTP407 с тестовыми прокси и реальным VPN Packet Tunnel; App Store релиз/отправку не выполнять автоматически.

## 30.10.2026 — iOS 0.1.41 (46): App Review submission

- [x] Apple created 0.1.41, processed signed build 46 to VALID and attached it; contains all 50 UI locales, PacketTunnel and real Yandex mobile banner integration.
- [x] Imported all 47 localized App Store ASO cards and 94 actual iPhone screenshots; every screenshot reached Apple COMPLETE state.
- [x] Preserved original privacy-policy URL exactly in all newly added market locales, without changing existing ru/en-US links or privacy questionnaire.
- [x] Submitted App Store version to Apple's review workflow; submission ID `57577081-0511-42b1-b05c-c01e26c27b9c`.
- [ ] External: await Apple review and publish automatically if accepted; verify App Store Connect READY_FOR_SALE.

## 30.10.2026 — iOS 0.1.41: восстановлен реальный баннер РСЯ, вычитаны 50 языков

- [x] По реальному опубликованному архиву 0.1.40 (45) восстановлены YandexMobileAds 8.6.0, блок R-M-20288304-1, флаг `-ObjC`, 228 официальных SKAdNetwork ID.
- [x] Исправлено соседнее расположение `TabView` и sticky-баннера: реальная демо-реклама с 50-ю переводами подписи отображается на iPhone SE, нижняя навигация не вытесняется. Проверены немецкий и иврит RTL с загруженным SDK-баннером.
- [x] Редакторская проверка 50 iOS-локалей: заменены два неактуальных поясняющих значения в каждой из 50 локализаций; 22 UI-термина исправлены вручную; 50 подписей рекламы локализованы; ключи/плейсхолдеры сохранены.
- [x] Полная техническая проверка всех 50 iOS-каталогов и 47 App Store ASO / 94 скриншотов; подписанный iOS 0.1.41(46) кандидат сохранён на SSD, не загружен в Apple.
- [ ] Релиз 0.1.41: после завершения CI и решения пользователя импортировать ASO, загрузить свежий IPA и отправить на Apple Review. Опубликованную 0.1.40 не менять.

## 30.10.2026 — iOS Home: гарантированно без прокрутки с местом под баннер

- [x] Исправлен `ContentView.swift`: iPhone Home больше не `ScrollView`, адаптивная компактная компоновка с кнопкой 56 pt, корректные переводы заголовков, приоритет управления подключением и видимый таббар.
- [x] Полная UI-матрица **50 языков × 7 сценариев = 350** проверок на SE 3, 13 mini, 17 Pro Max и SE 2 с увеличенным шрифтом, с баннерами 90/100 pt; дополнительно 20 проверок в Accessibility Extra Large. **370/370 pass** (+ 10/10 финальных проверок после увеличения области нажатия до 44 pt).
- [x] Сохранены 370 реальных SwiftUI геометрических измерений, 50 снимков симулятора и матрица в `docs/APL_IOS_HOME_BANNER_QA_MATRIX_2026-10-30.csv` (QA-артефакты на ArvectumSSD).
- [x] Подписан новый локальный iOS 0.1.41 (46) архив с PacketTunnel и 50 языками. Текущую отправленную заявку Apple 0.1.40 не менять.
- [ ] При реальном подключении баннерного компонента проверить фактический размер адаптивного баннера (текущие измерения выполнены с отладочной областью 90/100 pt), не менять текущую заявку Apple.

## 30.10.2026 — Подготовка iOS 0.1.41 (46) с полным ASO без изменения проверки 0.1.40

- [x] Проверены Apple API и действующая проверка: 0.1.40 WAITING_FOR_REVIEW, build 45; 0.1.41 ещё не создана.
- [x] Подписанная локальная 0.1.41 (46) с PacketTunnel и 50 языками, архив+IPA сохранены на ArvectumSSD, SHA256 в `docs/APL_IOS_041_ASO_RELEASE_PREPARATION_2026-10-30.md`.
- [x] Готовы 47 ASO-локализаций и 94 скриншота, сценарии read-only проверки, создания 0.1.41 после публикации 0.1.40, поэтапного импорта ASO и проверки Apple COMPLETE/MD5, доставки IPA и привязки VALID build 46.
- [x] Добавлены unit-тесты безопасности: отказ при 0.1.40 в App Review, защита от дубликатов и подмены версий/сборок, повторная проверка состояний.
- [ ] Внешнее условие: Apple завершит рассмотрение 0.1.40 и версия станет READY_FOR_SALE. Только после этого можно выполнить записывающие Apple API операции по подготовленному runbook.
- [ ] После создания новой версии и проверки импорта отправка 0.1.41 на App Review — отдельный явный этап выпуска; текущая проверка не затронута.

## 30.10.2026 — iOS 50 UI languages: editorial ASO package complete

- [x] GPT multilingual editorial + automated 50×155 iOS UI catalog consistency review; corrected erroneous bypass-exception terminology in 17 languages and disconnect action wording in three, plus literal `host:port` in eight.
- [x] Restored correct visible Arvectum wordmark in three iOS app UI placements; screenshot checked on Simulator.
- [x] Full editable App Store ASO corpus for 47 official Apple locales / 42 relevant iOS source languages: localized name, subtitle, description, keywords, promotional text, update text, and screenshot feature copy. Regional English/French/Spanish variants reviewed independently.
- [x] Real iOS Simulator screenshot pairs per locale: 94 Apple-compliant 1206×2622 opaque JPEG files; no fabricated product states.
- [x] Apple metadata/UTF-8 byte validation, 30 iOS/localization tests, all 50 `.strings` lint, signed full iOS archive and IPA export passed. App Store Connect remains unchanged.
- [ ] Optional external human linguistic certification, wider device/a11y QA and keyword ranking measurement can supplement the completed source package before a new ASO campaign.

## 30.10.2026 · iOS-only release localization: 50 source languages complete

- [x] 50/50 full **iOS** `.lproj` catalogs (155 translated UI strings per language); 10 new: ha, am, sv, da, fi, nb, bg, sr, hr, ca. Android/desktop not changed; cross-platform registry remains 40/50.
- [x] iOS native language picker and system scripts; 21 runtime mappings PASS, 50 plutil PASS; unsigned UI-only iOS Simulator bundle and signed App Store archive with PacketTunnel PASS; local QA IPA exported, **not uploaded**.
- [x] Default-size iOS simulator visual review: English, Amharic, Hausa, Serbian Cyrillic, Finnish and Hebrew RTL; retained source QA evidence in `/tmp`.
- [ ] Release signoff: review user-facing “no advertising/no ad SDK” claim versus advertising configured in published app; independent native language & device accessibility QA; choose new version/build number and submit only after owner's explicit approval.

## 30.10.2026 · Редакторская вычитка ChatGPT / Tier-3 черновики

- [x] В 40 полных локализациях исправлен контекст предупреждения Windows-автозапуска: чужие записи автозапуска, а не «записи других людей» или «сетевые настройки других программ»; сохранено название кнопки журнала.
- [x] Исправлены четыре английские строки узбекского desktop и одна французского Android; тест против длинных английских пропусков по всем 40 языкам.
- [x] Черновой редакторский материал для остающихся 10 языков: 280 переводов терминов (28×10) и 160 ключевых инструкций iOS (16×10) — ChatGPT-авторство, не локальная модель/внешний переводчик.
- [ ] Для статуса 50/50 заполнить весь корпус 155 iOS + 104 Android + 193 desktop на каждый язык, включая ошибки, сетевую диагностику, все сообщения автозапуска, редактуру и тесты.
- [ ] До релиза независимая носительская проверка и QA на устройствах; не менять Apple Connect и выключенный Watchdog.

## 29.10.2026 · APL Core-40: cs, sk, el, he (Tier-2 завершён)

- [x] Добавлены полные исходные каталоги чешского, словацкого, греческого и иврита: по 155 iOS / 104 Android / 193 desktop значения, всего 40/50 языков.
- [x] Для иврита добавлен RTL; 64 ключевые инструкции и 16 предупреждений сети отредактированы. Проверки Python и iOS/Android сборки прошли.
- [x] В таблице `docs/APL_LOCALIZATION_COVERAGE_2026-10-29.md`: Tier-1 — 20/20, Tier-2 — 20/20, Tier-3 — 0/10.
- [ ] Следом Tier-3: `ha`, `am`, `sv`, `da`, `fi`, `nb`, `bg`, `sr`, `hr`, `ca`.
- [ ] До релиза: носительская вычитка, реальное устройство, проверка RTL/доступности и подписанный PacketTunnel archive.

## 29.10.2026 · APL Core-36 — ms, fil, sw, ro, hu

- [x] Пять полных языков второго приоритета: малайский, филиппинский, суахили, румынский, венгерский (155 iOS / 104 Android / 193 desktop на язык). Всего 36/50.
- [x] Редакторские правки 80 ключевых инструкций и 20 предупреждений восстановления сети; 28 терминов × 5. Source parity, Python/iOS/Android тесты и сборки пройдены.
- [x] Таблица 50 языков, готовых и запланированных: `docs/APL_LOCALIZATION_COVERAGE_2026-10-29.md`.
- [ ] Следующие Tier-2: `cs`, `sk`, `el`, `he` (иврит RTL); Tier-3 после этого: `ha`, `am`, `sv`, `da`, `fi`, `nb`, `bg`, `sr`, `hr`, `ca`.
- [ ] Отдельные релизные проверки: независимая редактура носителями, физические устройства, переполнения/доступность, signed PacketTunnel.

## 29.10.2026 · APL Core-31: mr, gu, kn, ml, uz-Latn

- [x] Полные исходные локализации маратхи, гуджарати, каннада, малаялам и узбекского (латиница): по 155 iOS / 104 Android / 193 desktop строки, всего 31 язык.
- [x] Вычитаны 80 инструкций и 20 предупреждений сети; 28 терминов × 5; системный выбор локали, script-specific Uzbek Latin, source parity, Python и iOS/Android сборки.
- [ ] Отдельный QA перед релизом: независимая языковая редактура и физические устройства, доступность, длинные подписи, шрифты и названия Shortcuts.

## 29.10.2026 · APL Core-26 / ur, bn, pa-Guru, ta, te

- [x] Полные каталоги Tier-2 (урду, бенгальский, панджаби гурмукхи, тамильский, телугу), 155 iOS/104 Android/193 desktop на язык, итого 26 языков.
- [x] 28 терминов × 5, редактура 80 инструкций и 20 сетевых предупреждений, защита урду RTL; уточнение script-specific Punjabi Gurmukhi; tests, iOS Simulator UI-only и Android Public/Private.
- [ ] В отдельном QA: native-speaker proofread, физические устройства, VoiceOver/TalkBack, LTR IP/URL и полное зеркалирование Tk при необходимости.

## 29.10.2026 · APL Core-21 — hi/ar/vi/pl/th

- [x] Полные локализации хинди, арабского, вьетнамского, польского, тайского: 155 iOS + 104 Android + 193 desktop строк для каждого языка; всего 21 язык.
- [x] Терминологическая вычитка, исправление 80 инструкций и 5 сообщений восстановления сети; арабский RTL, LTR поля адресов/IP; 21 языковой тест, проверки Python/iOS/Android.
- [ ] До следующего релиза: визуальная QA на реальных устройствах, имена локализованных Shortcuts и корректная геометрия RTL в desktop; независимая носительская редактура при необходимости.

## 29.10.2026 · APL Core-16 / NL, ID, TR

- [x] Добавлено 3 полных языка из Core: нидерландский `nl`, индонезийский `id`, турецкий `tr`, по 452 строки/язык (iOS 155, Android 104, desktop 193).
- [x] Внедрены языковые селекторы и 28 терминов глоссария; вычитаны 54 длинные инструкции и 21 предупреждение о восстановлении сети; регрессионные тесты добавлены.
- [ ] Реальная UI/VoiceOver/TalkBack проверка всех трёх локалей перед включением в релиз. Документ QA: `docs/APL_CORE16_LOCALIZATION_QA_2026-10-29.md`.

## 29.10.2026 · Core-13: редактура + фарси (PR #272)

- [x] Повторная вычитка 12 существующих языков: 67 дополнительно исправленных текстов автоматизации, режимов и инструкций.
- [x] Полный корпус `fa` — 155 iOS, 104 Android, 193 настольные строки; iOS picker + RTL, Android RTL и desktop-поддержка текста справа налево; добавлены тесты.
- [ ] Приёмка персидского RTL на реальных устройствах и зеркалирование сетки Tk, если потребуется. См. `docs/APL_CORE13_PERSIAN_EDITORIAL_QA_2026-10-29.md`.

# Arvectum Proxy Launcher — canonical roadmap

## 31.10.2026 · iOS/macOS release reconciliation (supersedes dated snapshots below)

- **PUBLIC / VERIFIED:** Apple iTunes Lookup RU, app ID `6816013574`: **iOS 0.1.40 (build 45)** published **2026-10-30T17:04:45Z**. Historical 0.1.37–0.1.39 status claims below are not current.
- **0.1.38 PUBLISHED:** System/Light/Dark themes; arvectum.com support and marketing URLs.
- **0.1.39 PUBLISHED:** skippable onboarding, proxy-field help, System/Russian/English language selection, Yandex RSYA banner integration `R-M-20288304-1`.
- **0.1.40 PUBLISHED / ADS ACCEPTED:** moved banner into TabView safe area; added ad diagnostics. Owner confirms the RSYA banner is visible in published **0.1.40 and 0.1.41**; the 0.1.40 App Store review passed with the existing no-data-collected privacy declaration. Treat advertising implementation as **DONE**, not an open product blocker. The 0.1.41 public status is owner-reported (not independently Apple-Lookup-verified in this documentation update).
- **SOURCE INTEGRATION DONE:** iOS ads, Smart Exclusions, universal import, 50 iOS locales and 47 ASO locales merged to `main` in PR #278 (commit `b4e8a9fd`); 36 GitHub checks PASS, 4 conditional SKIPPED. Physical iPhone previously passed 3 import UI tests and running QR camera. No new App Store binary was uploaded by this merge.
- **iOS 0.1.41 (build 46):** 50 locale catalogs, 47 App Store ASO localizations and 94 iPhone screenshots were prepared and 0.1.41 submitted for Apple review; distinguish review submission from independently verified public availability. Source merged to GitHub `main` via PR #278; App Store review/publication is independent of source integration.
- **P1 IMPLEMENTED SOURCE / VALIDATED:** Smart Exclusions dependency scan and universal import (clipboard/files/QR/deep link) have Swift/simulator tests; iPhone 13 import UI tests 3/3 PASS and camera readiness confirmed. Real QR acquisition remains optional before release. **P1 OPEN:** failure diagnostics (offline/DNS/TCP/HTTP 407/tunnel), physical VoiceOver/accessibility QA.
- **P2 / RESEARCH:** widgets/quick actions, managed profiles and marketplace, advanced VPN transports, GOST VPN feasibility.
- **OWNER DECISION / ADS CLOSED:** do not repeatedly reopen speculative Apple VPN-advertising or privacy-declaration warnings. Preserve the accepted App Store privacy declaration; revisit only on material new evidence or explicit owner request. Apple approval is recorded for the submitted version, not as a blanket future ruling.
- **macOS 0.2.20:** signed build 10 was submitted for App Review; the build/upload obstacle is closed. Apple approval and publication are separate pending external results.
- **WORKTREE SAFETY:** Mac mini local `main` has uncommitted user changes. Do not reset/rebase/overwrite its checkpoint or working files; use a clean integration worktree.

## 29.10.2026 · Core-12 редакторский проход (PR #272)

- [x] Вычитка смысла и технических терминов на 12 языках для iOS/Android/desktop: 5424 записей проверены структурно, 425 переводов исправлены; каталог из 28 терминов и регрессионные проверки введены в source. См. [редакторский QA](APL_CORE12_EDITORIAL_QA_2026-10-29.md).
- [ ] Независимая редактура носителями, проверка точных названий Shortcut actions и UI на устройствах, VoiceOver/TalkBack, privacy/ads соответствие фактическому бинарнику — отдельные обязательные гейты до релиза.
- [ ] В исходном iOS тексте остаются старые фактические утверждения «Без аналитики и рекламы»; при появлении рекламного SDK они не должны попасть в новую сборку без сверки. **Текущую Apple карточку/подачу не менять этой задачей.**

## 29.10.2026 · APL localization / Core-12 — первая исходная волна

- [x] Из канонического реестра Arvectum Tools Core перенесена базовая 12-язычная матрица: `en`, `ru`, `es`, `fr`, `de`, `it`, `pt-BR`, `pt-PT`, `ja`, `ko`, `zh-Hans`, `zh-Hant` (источники, не магазинные карточки).
- [x] iOS: по 155 существующих UI/онбординг/приватность ключей на язык, 12 вариантов в переключателе и корректный системный fallback; Android: штатные ресурсы для 12 языков, статические надписи и динамические сообщения; desktop (macOS/Windows/Linux): 193 локализованные исходные фразы Tk и выбор по языку ОС.
- [ ] Следующая волна — расширять реестр только реально переведёнными каталожными наборами, начиная с `nl` (в Core пока частично), далее Tier 1 `hi, ar, id, tr, vi, pl, th`; задача будущей волны, не часть текущего релиза.
- [ ] Профессиональная редактура, реальный device/simulator GUI QA, экранные переполнения, accessibility, App Store локализованные карточки/скриншоты и отдельное разрешение публикации. Структурная полнота **не означает публикацию**.
- [ ] Полная iOS-сборка требует штатного patched `tun2proxy.xcframework` для CI/подписанного архива; локализации проверяются отдельно. Последняя версия в App Store Connect/проверке, карточки приватности и текущие бинарники этой задачей **не изменяются**.

[Матрица и условия приёмки](../localization/README.md).


## 28.10.2026 · C19 — macOS wake guard безопасное автоматическое восстановление UI

- [x] Текущий macOS GUI автоматически обновляет recovery controls после истечения wake guard без focus/click, повторный сон продлевает guard до безопасного expiry, а обычный Off остаётся доступным. 47/47 `test_proxy_gui` PASS (Python 3.12 + Tk 9.1); исходники в отдельном PR. [C19 QA](APL_MAC_WAKE_GUARD_C19_QA_2026-10-28.md).
- [ ] Реальная проверка сна/пробуждения MacBook, статуса proxy worker и Safari/ChatGPT, обновлённая подписанная сборка — не пройдены и не заявляются.


Updated: 2026-10-31 (iOS 0.1.40 public release verified; dated sections below are historical snapshots)
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Canonical branch: `main`  
Current stable product line: 0.2.16 — public release for Windows x64, Astra Linux 1.8 x86-64, RED OS 8.0.3 x86-64, generic Linux x86-64 AppImage and Developer ID-signed/notarized macOS Apple Silicon/Intel DMGs

Status legend: **DONE**, **PUBLISHED**, **CURRENT**, **READY NOW**, **READY**, **IMPLEMENTED**, **PARTIAL**, **HUMAN/LEGAL PENDING**, **STOP-GATE**, **PAUSED**, **DEFERRED**, **FUTURE**.

## 28.10.2026 · C18 публичная iOS-проверка (новее нижнего среза 27.10)

- [x] **APL iOS 0.1.38 опубликована:** Apple Lookup по одному ID на страну подтвердил `0.1.38` в **15/16** проверенных регионах, дата `2026-10-27T20:24:47Z`, RU минимум iOS 15.0. **CN — `resultCount=0`**, версия/причина недоступности неизвестны. [Доказательство](monetization/APL_IOS_C18_PUBLIC_CHECK_2026-10-28.md).
- [x] Исходники тем и Support/Marketing URL объединены PR #265; прежняя запись ниже «не опубликовано» относится только к исходному состоянию 27.10, **не** к текущему магазину.
- [ ] Реклама в iOS APL пока отсутствует, Apple VPN Guideline 5.4 и vendor ad-data STOP-GATE сохраняются; [план](monetization/ios-appstore-advertising.md). Публикация новой версии/SDK/metadata только по отдельному разрешению.

## Синхронизация 27.10.2026 · мобильные приложения, продуктовая очередь

Этот блок новее исторических дат ниже. Последний стабильный desktop baseline в GitHub `main` на момент сверки — 0.2.16; точную публичную версию по каждому каналу и статус Mac App Store 0.2.19 (8) необходимо перепроверить, а не считать прошлую подачу публикацией.

- [x] Android: рабочий мобильный VpnService/TUN, профили, failover, реальная 0.1.17 опубликована; 0.1.19 site exclusions интегрированы и физически принимались, но факт публичного релиза этой версии требует отдельной проверки.
- [ ] Android P0/P1: MOB-004 Yandex Ads и двухканальная дистрибуция (публичный APK с рекламой и приватный без SDK), решение об update/package identity, consent/QA/реальные устройства. Монетизация — owner-gated, не запускать автоматически.
- [x] **iOS APL:** опубликована **0.1.37 (build 41)**; Apple API verified в [PR #264](https://github.com/arvectum2/proxy-launcher/pull/264); владельцем сообщено 100+ установок (количество не сверено с ASC Analytics). Старую запись 0.1.36 (40) как текущую считать ошибочной.
- [x] iOS P0 **реализовано в PR #265**, не опубликовано: выбор System/Light/Dark, сохранение AppStorage, семантические цвета на основных экранах; **0.1.38 (build 42)** подписан и IPA экспортирован, пакетные тесты PASS. [ ] Отдельно нужны CI/слияние, физическая проверка VoiceOver/контраста и проверка фактического Apple Review/publication.
- [x] iOS P0: **https://arvectum.com/app-ads.txt** проверен; 0.1.38 (42) [PR #265](https://github.com/arvectum2/proxy-launcher/pull/265) готовит **Support URL и Marketing URL = https://arvectum.com/** для RU/en-US, ASC metadata write/readback HTTP 200. [ ] В опубликованной 0.1.37 ссылки **не изменены** (Apple API 409 STATE_ERROR при попытке правки READY_FOR_SALE); подтвердить live после отдельного релиза.
- [ ] iOS P1 реклама: план в [PR #262](https://github.com/arvectum2/proxy-launcher/pull/262), [issue #261](https://github.com/arvectum2/proxy-launcher/issues/261). В **0.1.38 (42) рекламного SDK нет**. Прежде чем внедрять нативный баннер РСЯ, пройти юридическую/Apple App Review Guideline **5.4 (VPN-app advertisement)** проверку, privacy/consent, real fill/no-fill и доходность; не обещать рекламу в VPN-клиенте как заранее разрешённую.
- [ ] Common P1: Smart Exclusions — on-device анализ зависимых доменов (например, gu-st.ru для gosuslugi.ru), понятное управление, защита privacy/rollback; не смешивать с уже реализованным ручным исключением.
- [ ] Research: коммерческий ГОСТ-VPN клиент для Apple/macOS/iOS — API/криптография, интероперабельность, правовая квалификация, лицензирование и сертификация, App Store допуск; **не заявлять сертификацию или совместимость до проверки**.
- [ ] Desktop: Windows full-trust publisher signing; per-app routing architecture; macOS production notarization и Store status; Linux acceptance. Сохранять fail-safe rollback/owner gates из канонического плана.

**Граница:** без отправки новых App Store/Google/RuStore билдов, изменений опубликованных карточек, сертификатов или платного API. Проверка статуса — read-only. Бэклог не равен одобренной разработке каждой отложенной ветки.


## 0. Repository authority and release baseline

- **DONE** — source/history/tags were recovered into `arvectum2/proxy-launcher`; `main` is the canonical integration branch.
- **DONE** — current governance, installer/support and repository-identity references are normalized to the canonical slug without rewriting historical provenance.
- **DONE** — GitVerse mirror logic is owner-independent on the GitHub side and current GitHub/GitVerse release mirroring is operational.
- **DONE** — exact-SHA GitHub Actions evidence was rebuilt in the canonical repository for Windows portable, Windows installer/Gate R6, SAST, SBOM, provenance and release evidence.
- **DONE** — `main` protection is governed by the active `Protect main` ruleset; PR + required `build` enforcement and negative merge acceptance have been proven.
- **DONE** — stale Windows PowerShell 5.1 signing-chain encoding contract was corrected in PR #43; `Windows Russian-first Production Signing` is green again without changing production signing behavior.
- **MIGRATION CLOSED** — the `arvectum1 -> arvectum2` repository migration is no longer an active project gate.

Historical repository identifiers remain valid only inside explicit provenance, closed acceptance, immutable baseline or historical workflow material. They are not current operational authorities.

## 1. Current stable product line

- **CURRENT / PUBLISHED — v0.2.16** (published 2026-09-25): Windows x64 Setup + portable ZIP, Astra Linux x86-64 DEB, RED OS 8.0.3 x86-64 RPM, generic Linux x86-64 AppImage, Developer ID-signed/notarized macOS Apple Silicon + Intel DMGs, plus SHA256SUMS.txt.
- **EXACT RELEASE OBJECT** — immutable v0.2.16 annotated tag/release points to `6799297bf1492d352ca9d78a0a49b2adf3345d2a`; GitHub asset digests, exact-SHA Release Evidence Package, Developer ID/notarization evidence and GitVerse public payload parity were verified.
- **POST-RELEASE METADATA ONLY** — any main commits after the v0.2.16 tag are documentation/checkpoint reconciliation only unless a later product task explicitly changes the product version.
- **v0.2.11** (published 2026-09-20) carried the Windows PAC/WPAD isolation fix and macOS Safari/CONNECT routing hardening.
- **v0.2.12** publishes the verified macOS long-sleep recovery and Android long-sleep/foreground VPN reconciliation while preserving immutable v0.2.11.
- **CURRENT SAFETY CONTRACT** — Windows rollback/recovery retains saved-or-Arvectum ownership/fail-closed semantics; Astra/Fly and RED OS/KDE real-host acceptance remain valid unless a material platform/recovery change requires rerun.
- **DONE / MAC PHYSICAL** — the v0.2.12 macOS long-sleep fix has real MacBook acceptance evidence: roughly 96 seconds Maintenance Sleep recovered without disabling APL or restarting the browser, with fresh CONNECT 200 after wake.
- **DONE / MAC TEST DISTRIBUTION** — `v0.2.10-macos-test.1` and `v0.2.10-macos-test.2` arm64 prereleases exist for dogfood. They are not the stable public macOS lane and do not imply Developer ID/notarization.
- **HISTORICAL ANCHOR** — v0.2.5 remains the first physically sealed Windows CFA-safe baseline and immutable provenance anchor.
- **HISTORICAL PROGRESSION** — v0.2.6 Windows+Astra; v0.2.7 RED OS; v0.2.8 Linux recovery hardening; v0.2.9 Windows recovery symmetry; v0.2.10 AppImage promotion; v0.2.11 PAC/WPAD + Safari routing fixes; v0.2.12 long-sleep recovery.

Current canonical main verified before this roadmap update: 6b3a9c4a2b18585487a3df0504d9b62b0110a292.
## 2. Russian-first release trust and Windows public trust

- **DONE** — APL-REL-010 real Rutoken/CryptoPro detached-signature POC and the Russian release-evidence architecture.
- **DONE / HISTORICAL EVIDENCE** — company УКЭП/CryptoPro remains RELEASE-EVIDENCE-ONLY; it is not Microsoft Authenticode/SmartScreen publisher trust.
- **DONE** — APL-REL-011/012/013 release manifest, verification UX and fail-closed Russian production release gate.
- **CURRENT PUBLIC RELEASE** — v0.2.16 is published without native Windows Authenticode; macOS Developer ID/notarization is a separate platform trust path.
- **READY FOR REVIEW REFRESH — issue #30, PR #161** — #161 is the latest substantive APL-REL-016 packet, but it became stale after later unsigned releases. With immutable v0.2.16 now public, refresh/rebase from current main and make **v0.2.17+** the first eligible future native Authenticode/public-trust release.
- **SUPERSEDED REVIEW HISTORY** — PRs #132 and #157 preserve older v0.2.10/v0.2.12-era preparation but are not the current packet.
- **OWNER GATE** — after refresh, provider/certificate selection, spend, key custody, packet merge as an approved decision, production signing and release remain Owner-reserved.
- **RULE** — never retrofit embedded signing into an immutable published release; every trust change belongs to a new version.

## 3. IP / legal / sovereignty

- **DONE** — APL-IP-002 platform sovereignty audits.
- **DONE** — APL-IP-003 canonical source refactor, Slices 1–23.
- **DONE** — APL-IP-004 promoted-artifact third-party license bundle engineering.
- **[Web] DONE — post-APL-IP-004 review reconciliation** — historical governance anchor remains candidate `ef9846e151a2e4e7046169e0787603969018cc97`; later v0.2.9 filing evidence does not rewrite that historical review.
- **HISTORICAL CONTRACT — CONDITIONAL / POST-APL-IP-004 ENGINEERING RECONCILED / HUMAN-LEGAL PENDING.** This phrase is retained solely for the historical clean-IP/legal-baseline contract; it does not mean the current registry filing-evidence packet is blocked.
- **[Web after explicit APPROVED] — create governed clean-IP baseline/tag** only if a distinct clean-IP/legal-baseline action is deliberately reopened.
- **DONE FOR CURRENT FILING EVIDENCE — APL-IP-001 / v0.2.9.**
- **HISTORICAL ANCHOR** — v0.2.5 remains the first physically sealed Windows CFA-safe IP/provenance baseline; its source/tag/artifact evidence and 2026-09-14 packet are preserved and are not rewritten.
- **DONE / EXACT-OBJECT ENGINEERING** — accepted v0.2.9 source commit `ca7c1019...`, source tree `55f2d50f...`, immutable tag commit `d13d9dac...` and promoted release-package digests are governed.
- **DONE / EXACT-TREE EVIDENCE** — provenance run `35255499712` and CycloneDX SBOM run `35255499669` bind to the exact released source tree.
- **DONE / ENGINEERING DRIFT RECONCILIATION** — material v0.2.5 -> v0.2.9 evolution is classified across Astra/Linux, RED OS/RPM, Linux recovery and Windows rollback-ownership slices.
- **DONE / OWNER FACTS** — the actual 2026-09-14 private sole-participant/rightsholder decision was reviewed; it identifies Arvectum Proxy Launcher without a version number, transfers the exclusive right in full and authorizes modification/reworking. Current Rospatent, corporate/Russian-control and human creative-control facts were confirmed by the Owner.
- **v0.2.9 HISTORICAL SCOPE** — Windows Setup + portable, Astra DEB and RED OS RPM. Owner directive 2026-09-18 separately admits AppImage for the next release; immutable v0.2.9 evidence is not rewritten.
- **PROCESS CORRECTION** — the previously prepared R-1B two-party/self-signing future-rights agreement is not a mandatory APL-IP-001 or registry-filing step. It is retained only as optional external legal hardening for the residual question of later human-authored copyrightable contributions. Do not reintroduce it as a blocker without new Owner/legal input.
- **RULE** — repository evidence is not a legal opinion. If the registry/expert or external counsel specifically requests a stronger chain-of-title instrument for later contributions, handle that as a targeted legal-hardening task rather than per-version compliance ritual.

Canonical current records: `docs/APL_IP_001_V0_2_9_SIGNOFF.md`, `docs/evidence/APL_IP_001_V0_2_9_CANDIDATE_RECONCILIATION_2026-09-18.md`, `docs/evidence/APL_IP_001_V0_2_9_OWNER_FACT_CONFIRMATION_2026-09-18.md`. Historical v0.2.5 records remain evidence.

## 4. Linux / Astra Linux

- **DONE** — APL-LNX-001..009 engineering: environment detection, NetworkManager preflight, capability/PolicyKit UX, autostart, diagnostics, Debian packaging and CI acceptance.
- **DONE / PHYSICAL PASS** — APL-LNX-010 / Gate R8 on Astra Linux Special Edition 1.8/Fly. Real-host evidence covers install, GUI/runtime, NetworkManager enable/disable, exact rollback, crash/reboot recovery, autostart, package lifecycle, diagnostics/privacy and cleanup.
- **DONE** — APL-LNX-011 fixed Firefox system-proxy behavior on Astra/Fly and was closed by PR #71/#72.
- **CURRENT RELEASE** — v0.2.16 publishes Arvectum-Proxy-Launcher-0.2.16-astra-linux-amd64.deb; v0.2.9 remains the governed registry-filing evidence baseline.
- **PROMOTED LANE** — Debian .deb remains the preferred Astra/Linux package.
- **PROMOTED FOR NEXT RELEASE** — the x86_64 AppImage lane uses the same canonical Linux frozen executable, hash-pinned appimagetool/type-2 runtime, embedded runtime/third-party notices, exact-main CI reuse and release checksum coverage. `v0.2.9` remains unchanged.
## 5. Russian Software Register / APL-REG-001

This is an active compliance/filing workstream, but repository dossier preparation is now substantially complete.

- **DECIDED WORKING CLASS** — 02.02 — Программы обслуживания, subject to live classifier/law recheck immediately before filing.
- **DONE / PHYSICAL** — first trusted-OS acceptance record: Astra Linux SE 1.8.
- **DONE / PHYSICAL** — second trusted-OS acceptance record: RED OS 8.0.3 Standard Desktop x86-64, merged in PR #83.
- **DONE** — APL-REG-001D filing-grade documentation dossier for v0.2.9 merged in PR #95; final checkpoint PR #96 records 6/6 focused dossier tests and 10/10 exact-head GitHub workflows successful.
- **CURRENT LEGAL TIMING BASELINE** — under the official baseline rechecked on 2026-09-17, the two-trusted-OS condition for class 02.02 starts on **2027-01-01**. Existing Astra/RED acceptance is retained as future-proof compatibility evidence; exact v0.2.9 reruns are preferred but are not represented as a current 2026 filing prerequisite.
- **PRE-SUBMISSION / HOLD** — external filing is blocked on real HUMAN/PRIVATE/PHYSICAL evidence: exclusive-right/corporate/Russian-control chain, applicable foreign-payment/accounting evidence, APL-REG-001B physical sovereign lifecycle proof, factual Russian support/modification contacts, final exact-v0.2.9 Russian-GUI visual review, signer authority/qualified electronic signature, and a live law/portal recheck.
- **HARD STOP** — automation must not sign or submit the Ministry/registry application or ingest УКЭП/private-key material.

Canonical dossier: docs/registry/. Canonical pre-submission gate: docs/registry/APL_REG_001F_PRE_SUBMISSION_AUDIT.md.
## 31.10.2026 · macOS 0.2.20 build 10 — corrective TLS relay resource lifetime (QA)

- [x] One-hour TestFlight build 9 run FAILED: 101 TCP, 81 CLOSE_WAIT, 9 HTTPS failures, later VPN disconnected. Do not publish build 9.
- [x] Implement HTTPS TLS relay cap (90 connections), 90-second idle reaper / 15-minute max age, guaranteed stop cleanup; signed Release build 10 archived, focused tests PASS.
- [x] Apple server validation/upload: build 10 VALID; Internal TestFlight IN_BETA_TESTING; 0.2.20 draft linked to build 10; Russian release notes ready.
- [x] Live TLS-relay integration: 105 local TCP clients, 90 upstream max, 0 after 90-second inactivity cutoff (PASS).
- [x] Build 10 installed on MacBook; 65-minute soak complete (66 samples): zero HTTPS/VPN/Tailscale failures, stable tunnel PID; 81 TCP max, transient CLOSE_WAIT peak 40 early, draining to 24 TCP/3 CLOSE_WAIT at the end. Human QA accepted with documented threshold warning (raw automatic REVIEW retained).
- [ ] After green PR CI and metadata validation, merge PR #274 and submit build 10 to macOS App Review with MANUAL release. Do not change live macOS 0.2.19 or pending iOS review.

## 30.10.2026 · macOS 0.2.20 / build 9 — socket-pressure hardening, INTERNAL QA

- [x] Apple TestFlight build 9 (0.2.20) processed as VALID; internal group active; saved profiles retained on MacBook.
- [x] Exact pinned patched tun2proxy rebuilt; Debug/Release/extension compiled; CI checks green; PR #274.
- [x] macOS Packet Tunnel bounds CLOSE_WAIT/TCP pressure and TLS relay releases closed connections; legacy external guard unloaded and autostart disabled on QA MacBook.
- [ ] Physical one-hour soak under ordinary load (passive MacBook JSONL monitor launched; first ~18 min stable), verify resilience and real primary recovery when PX6 becomes reachable.
- [x] Deterministic primary/backup/failback policy smoke 10 assertions PASS; PR #274 CI previous run 19 PASS / 4 skipped. Created macOS 0.2.20 App Store draft; current public 0.2.19 untouched.
- [ ] Apple Developer Program License Agreement updated: Account Holder must accept before new public review submission; Admin session cannot accept. Once both physical QA and Apple agreement gates pass, associate TestFlight build 9, finalize ru What's New and submit macOS review.

## 6. macOS

- **DONE** — APL-MAC-001..008 engineering/acceptance track and Gate R9 evidence retained.
- **DONE / TEST DISTRIBUTION** — arm64 prereleases `v0.2.10-macos-test.1` and `v0.2.10-macos-test.2` were published for dogfood and mirrored with checksum parity.
- **DONE / ROUTING + WAKE HARDENING** — PRs #141/#143/#146/#149 plus later v0.2.14/v0.2.15 recovery work close the current direct-distribution routing/sleep baseline.
- **PRODUCTION DISTRIBUTION — DONE / PUBLISHED v0.2.16** — exact-main ARM64/Intel packages were promoted through the Arvectum Mac mini, signed with Developer ID Application, Apple-notarized/stapled, Gatekeeper-verified, published and mirrored with payload parity.
- **NEXT DIRECT DESKTOP RELEASE — MANDATORY macOS recovery inclusion (v0.2.17+).** Carry forward PR #203 (reserved wake-refresh fail-closed sentinel recovery) and PR #207 (exact-endpoint HTTP/HTTPS enable-bit drift recovery). Release acceptance must physically verify: APL start → induced exact-endpoint enable-bit drift → rollback exit 0 → all saved network services match the pre-APL snapshot → direct and ordinary HTTPS succeed → legacy 127.0.0.1:1080/8082 tunnel remains untouched. Do not ship the next direct macOS desktop build from a source point older than merge commit 46aef7ecfd165aa03145d2a74d4aba1ba44d972d.
- **MAC APP STORE — CURRENT 2026-10-14: v0.2.19 build 8 WAITING_FOR_REVIEW / MANUAL RELEASE.** Owner verified Safari site exclusions in TestFlight, Apple accepted the review submission; publicly available macOS Store version remains v0.2.17. The Store lane remains separate from immutable direct v0.2.16. The following build1–3 notes are historical.
  - Initial build 1 was submitted on 2026-09-26 and rejected on 2026-09-28 under Guidelines 2.1.0 App Completeness and 2.4.5 Hardware Compatibility.
  - PR #223 merged the binary remediation at `ad09b2393def6c498daa8d67d2439b1d1aac9502`: passive launch no longer mutates Network Extension preferences, Store help no longer advertises GitHub/self-update behavior, and the Catalyst minimum was corrected.
  - Build 2 remains intentionally unused because its uploaded metadata reported macOS 12.0 minimum.
  - Build 3 remains the accepted binary: ARM64 Mac Catalyst + PacketTunnel, `LSMinimumSystemVersion=13.0`, Apple validation PASS, physical passive-launch smoke PASS, `usesNonExemptEncryption=false`.
  - Apple returned a second review response on 2026-10-01 covering Guideline 5.2.5 product naming plus Guideline 2.1 reviewer access and VPN/data-handling questions. These were metadata/reviewer-information issues, not a new binary defect.
  - On 2026-10-02 the App Store name was changed to `Proxy Launcher by Arvectum`; App Review Information was updated with working reviewer-access instructions and direct VPN/data answers; a reviewer reply was sent; the existing build 3 review item was resolved and resubmitted without rebuilding.
  - **HISTORICAL ASC STATE (2026-10-02):** v0.2.17 (3) was `WAITING_FOR_REVIEW`; it subsequently became public. Current review is v0.2.19 (8), MANUAL release, independent of this old submission.
- **MANDATORY HELP UX — DONE / PHYSICAL PASS.** The standard macOS Help item opens bundled offline help.
  - Direct Developer ID builds may expose GitHub/release links appropriate to direct distribution.
  - Mac App Store builds must remain useful offline and rely on App Store update semantics; the build-3 remediation removes competing GitHub Releases/self-update language from the Store help flow.
  - Core offline sections remain: **Getting Started**, **status meanings**, **proxy formats**, **Troubleshooting**, **About & Privacy**.
  - No Store build may ship a competing self-updater.
- **OPTIONAL FUTURE** — keep `.app`/DMG as the normal direct macOS distribution lane; add a separate portable form only if it provides real benefit without weakening recovery/update semantics.

## 6A. Smart Exclusions — automatic related-site discovery (APL-SMART-001..004)

**OWNER-APPROVED / PLANNED FOR A LATER SPRINT (2026-10-14). NOT PART OF MAC APP STORE 0.2.19 (8).** The user enters one website, and APL discovers its essential supporting domains, maintains a safe local dependency graph and routes those connections directly. Release 0.2.19 (8) has been signed, physically tested and submitted for Apple App Review; do **not** modify or rebuild that binary for Smart Exclusions.

**Baseline / motivating case:** Safari loaded the main `www.gosuslugi.ru` HTML directly (HTTP 200), but lacked styles and JS because the separate `gu-st.ru` asset host was still proxied. PR #255 manually added the verified dependency and is merged; owner confirmed build 8 works. This is a hard-coded workaround, not discovery.

### Phase A — local dependency analysis and test (APL-SMART-001)

- Offer an opt-in **Умное исключение** on a parent URL. A bounded on-device WebKit analysis checks initial redirects, scripts/module imports, CSS, fonts, images, API/fetch hosts and CDN assets when observable. Auth-gated routes and dynamic resource origins require later learning/confirmation; no user passwords, TLS interception or unrelated browsing history.
- Build a local graph `root site → host → resource type/source → confidence/last seen`. Classify first-party/necessary assets separately from analytics, ads and broad third-party/CDN domains. Auto-exclude high-confidence necessary origins only; request confirmation for ambiguous hosts. Enforce maximum graph size and expiry.
- Test **full loading**, not only DNS, TCP or main-frame HTTP 200. Show site-health status, missing resources, retry and manual fallback. Validate `www`, redirects, CNAMEs, A/AAAA, changed IPs, third-party shared CDN, blocked assets, and inaccessible/login-protected flows.
- **DoD:** the user adds only `gosuslugi.ru` and APL discovers `gu-st.ru` without a Gosuslugi-specific hard-coded mapping; physical Safari page fully renders with APL active; `github.com` and unrelated hosts remain on selected proxy. Tests include at least two unrelated real sites. Ship in a NEW feature version, not App Store 0.2.19.

### Phase B — usable rules and bounded refresh (APL-SMART-002)

- Present one parent exception with an expandable, auditable list of auto-discovered child hosts, reason, confidence, last check and owner override. Provide single removal, clear with confirmation and Undo; shared dependency removed only when no other parent references it.
- First use existing macOS/iOS `PacketTunnelProvider.resolveExclusions` and patched tun2proxy DNS `--dns-bypass`: apply both real-IP `NEPacketTunnelNetworkSettings.excludedRoutes` and DNS mappings together, with bounded refresh/reconnect, TTL/IPv6 handling, rollback and clear failure messages. **Do not claim runtime rule editing already exists.**
- Store minimal metadata **on-device**, with user-controlled retention and deletion. Never silently upload browsing logs, secrets or dependency graphs.
- **DoD:** changes survive restart, cleanup is complete, unrelated VPN traffic never silently bypasses its configured proxy, and updates fail safely if DNS or the proxy is unavailable.

### Phase C — dynamic Rust direct/proxy routing (APL-SMART-003)

- Research and prototype a **per-domain/per-connection policy engine** in Rust tun2proxy and Network Extension with direct physical egress, instead of relying on startup-only IP `excludedRoutes`. Validate Apple extension/platform capabilities and safe socket binding before architectural commitment.
- Handle DNS TTL/CNAME/cache changes, IPv4/IPv6, shared CDN IPs, TCP/TLS/WebSocket, UDP/QUIC/HTTP3 where feasible, DNS-over-HTTPS and ECH visibility limitations; avoid DNS leaks, bypass of arbitrary third-party traffic, proxy credential disclosure or direct/utun routing loops.
- **DoD:** new flows observe updated site rules without toggling VPN, non-excluded flows remain proxied, shared-IP and sleep/reconnect/failure regression tests pass on a real MacBook; Android/iOS parity requires separate platform acceptance.

### Phase D — optional Safari extension / runtime learning (APL-SMART-004)

- Consider Safari Web Extension for *per-navigation* dependency attribution after interactive login only with explicit installation and per-site permissions. Do not make the extension mandatory or assert full visibility into every browser/protocol; keep an understandable fallback on Chromium/Firefox.
- Retain observations locally, avoid surveillance of unrelated tabs or credentials, and recheck App Store VPN rules/privacy declarations before requesting permissions.

**Honest promise:** minimize manual domain management, proactively discover and repair gaps, but never promise 100% guaranteed success for arbitrarily dynamic/authenticated sites. Start a separate task/branch after 0.2.19 review; shipping requires real browser QA and owner authorization.

## 7. Per-application routing — application exclusions and desktop enforcement

- **DONE** — APL-ROUTE-001 platform-neutral routing-rule model.
- **DONE** — APL-ROUTE-002 per-platform feasibility matrix.
- **AUTONOMOUS COMPLETE / LOCAL-NATIVE PENDING** — APL-ROUTE-003 Windows read-only/control-plane prototype.
- **DONE** — APL-ROUTE-004 durable ownership/recovery/security journal.
- **APPLICATION EXCLUSIONS CONTROL PLANE — IMPLEMENTED.** PR #183 added deterministic application-exclusion persistence/capability semantics plus Android live enforcement through `VpnService.Builder.addDisallowedApplication`.
- **ANDROID UI / CURRENT MAIN — 0.1.38 / versionCode 39.** The accepted adaptive/profile/application-exclusion baseline is retained; PR #221 layers the current public/private Android distribution flavors on top without regressing manual profiles, Auto, site exclusions or application exclusions.
- **iOS CONSUMER PATH — SHORTCUTS AUTOMATION.** Native unmanaged consumer iOS cannot truthfully offer arbitrary Per-App VPN selection; PRs #185/#187/#189 provide the supported consumer workaround using APL App Intents + Shortcuts Opened/Closed automations. Managed/MDM Per-App VPN remains a different future capability.
- **WINDOWS PRODUCTION ARCHITECTURE — OWNER SELECTED / IMPLEMENTED / PHYSICAL PASS.** Production per-application routing uses the official signed WinDivert 2.2.2 stack plus the narrow Arvectum routing service and local proxy. PR #241 merged the production implementation to main at `61fcf2c0fae1e1b0ca93b2271eb3b907f49db352`; PR #243 merged the physical-installer compatibility fix at `f61f506761c79a882470ebdbf9f34a1aab9baf28`. The Arvectum-owned custom WFP callout path is lab-only and is not the production architecture.
- **WINDOWS PHYSICAL E2E — DONE.** Exact-head Windows CI passed for installer, portable, WinDivert production and public-trust gates. Physical `ArutyunovNS` acceptance proved fresh install, GUI-selected `curl.exe` DIRECT vs unselected `powershell.exe` PROXY, live rule removal/re-add, disconnect/reconnect, forced-runtime-crash rollback and active-session reboot recovery. The production path does not require an Arvectum-owned Microsoft kernel-driver signing certificate.
- **RELEASE BOUNDARY.** These merges update current main only. Published desktop v0.2.16 remains immutable and must not be represented as containing this later Windows per-app implementation. Shipping it requires the next explicit Windows desktop release task and release acceptance.
- **ANDROID ACCEPTANCE BOUNDARY** — implementation and UI are merged, but do not invent the dedicated public-IP bypass proof if it has not been recorded separately.
- **APL-UI-001 GATE — DONE.** The cross-platform Adaptive UI was merged in PR #193 by explicit Owner decision; the remaining unavailable physical-platform acceptance was waived for that merge only and is not claimed as performed.

## 7A. Cross-platform Adaptive UI — APL-UI-001 — DONE / MERGED

Design decision source: `docs/APL_UI_UX_CROSSCHECK_20260926.md`.

- Shared navy/mint tokens, profile/exclusion language, connection-state semantics and one stateful primary Connect/Disconnect action are implemented across supported UI families.
- Mobile remains touch-first; desktop uses compact sidebar/desktop composition and native platform conventions.
- Top-level information model is Home, Profiles, Activity/Diagnostics and Settings.
- macOS recovery-state Home CTA was corrected during physical review.
- Focused desktop/UI regression suite passed 53/53; exact-head cross-platform/security CI was green.
- PR #193 merged on 2026-09-27 after explicit Owner instruction. Unperformed host-specific acceptance is not relabeled as PASS.

## 7B. Universal connection input and managed configuration — APL-CONNECT-001 — FUTURE / PRODUCT-APPROVED

**Product principle:** APL should accept whatever connection material the user already has and keep protocol complexity out of the primary UX. The primary action remains one simple **Add connection / Connect** flow; protocol names and routing internals belong in detected details or an Advanced section.

- **ORDINARY PROXY — RETAIN CURRENT SIMPLE PATH.** Accept `host:port`, `host:port:login:password`, URL-form proxy credentials and the existing manual host/port/login/password fields. Preserve current APL Auto transport behavior across HTTP CONNECT, SOCKS5 and TLS-to-proxy HTTPS instead of forcing the user to select a protocol.
- **VPN LINK / KEY / CONFIG IMPORT — NEW.** Add paste/clipboard, file, QR and deep-link ingestion with deterministic scheme/config detection. Do not label arbitrary opaque text as supported until the corresponding engine can actually connect with it.
- **FIRST ADVANCED FULL-TUNNEL TARGET — VLESS + REALITY.** This is the preferred first VPN-protocol expansion because it matches the planned Arvectum VPS/VLESS+Reality infrastructure and gives Marketplace-issued configurations a native APL path. Keep VLESS/Reality details hidden by default after import.
- **SECONDARY ADVANCED TARGETS — DEMAND DRIVEN.** Evaluate WireGuard/AmneziaWG next; Shadowsocks, Trojan, VMess and Hysteria2 remain later compatibility candidates rather than reasons to turn the main UI into an Xray/sing-box control panel.
- **MTPROTO — TELEGRAM-SPECIFIC CONNECTION TYPE.** Accept manual `server + port + secret` plus standard Telegram proxy links (`tg://proxy...` / `t.me/proxy...`). Treat MTProto truthfully as a Telegram-specific proxy profile: APL may store/manage it and hand it off/open it in Telegram, but must not present MTProto as a device-wide VPN transport.
- **QR / CLIPBOARD / DEEP LINK — REQUIRED IMPORT SURFACES.** A user receiving a supported proxy/VPN/MTProto configuration should be able to scan, paste or open it in APL without retyping credentials.
- **SUBSCRIPTION / MANAGED PROFILE — FUTURE.** Support a URL-backed managed connection collection with bounded automatic refresh, explicit last-refresh/error state and safe rollback to the last known-good configuration. This is the preferred delivery mechanism for Arvectum-managed or third-party provider profiles.
- **MARKETPLACE ZERO-CONFIG DELIVERY — FUTURE.** After purchase, the issued connection should appear in APL automatically; the normal customer should not need to see or copy host/port/login/password or VLESS internals unless they explicitly request/export them.
- **QUICK ACTIONS — FUTURE UX.** Provide connect/disconnect/toggle through platform-appropriate Shortcuts, widgets or Control Center/quick settings where supported, while preserving the existing iOS Shortcuts application-routing workflow.
- **KILL SWITCH — FUTURE / CAPABILITY-GATED.** Expose only on platforms/modes where APL can guarantee fail-closed full-tunnel semantics. Do not use the label for ordinary desktop system-proxy mode unless non-APL direct traffic is actually blocked.
- **LOCAL-FIRST SECRET HANDLING — REQUIRED.** Imported credentials/keys remain in platform secure storage (Keychain/Keystore or equivalent) and must not be uploaded to Arvectum merely because the user pasted or scanned them. A managed Marketplace/subscription flow may contact the issuing backend only as explicitly required to provision/refresh that managed profile.
- **EXPORT/SHARE SAFETY — REQUIRED.** Any export/share action containing secrets must be explicit, preview what will be exposed and never leak credentials through logs, analytics, crash reports or ordinary diagnostic bundles.

### APL-CONNECT-001 staged delivery

1. **Stage A — universal importer shell:** normalize proxy text/URLs, QR, clipboard and deep-link entry; add MTProto profile detection + Telegram handoff; keep current HTTP/SOCKS/HTTPS engines unchanged.
2. **Stage B — VLESS + Reality:** select/pin the engine, implement cross-platform secure profile storage and full-tunnel connection path, then physically validate mobile and desktop behavior before claiming support.
3. **Stage C — managed subscriptions:** signed/validated remote profile refresh with last-known-good rollback, explicit provider/source identity and no silent downgrade to an insecure transport.
4. **Stage D — Marketplace zero-config:** purchase/provision/refresh integration so an Arvectum-issued connection becomes usable in one tap.
5. **Stage E — compatibility expansion:** WireGuard/AmneziaWG first, then additional protocols only when demand/partner interoperability justifies their maintenance cost.

**Anti-clone rule:** competitor breadth is input for compatibility, not the product identity. APL remains optimized for the shortest path from credentials/key/QR to a working connection; advanced routing engines, GeoIP/Geosite rules, raw JSON and protocol diagnostics stay out of the default flow.

## 7C. macOS application exclusions — APL-MAC-PERAPP — FUTURE / PRODUCT-APPROVED

**Goal:** bring real application exclusions to macOS where technically supportable: selected applications use **DIRECT** while other traffic follows the active APL proxy/VPN route, with the same understandable user model as Windows/Android.

- **DIRECT DEVELOPER ID PATH — PRIMARY CONSUMER TARGET.** Treat arbitrary consumer per-app exclusions as a separate macOS networking architecture task, not as a small extension of the current system-proxy/PacketTunnel implementation. The feasibility prototype must choose a supported Network Extension/System Extension design that can attribute flows to their originating application and selectively route them DIRECT or PROXY.
- **MAC APP STORE PATH — CAPABILITY-GATED.** Do not promise arbitrary unmanaged-consumer per-app selection in the Store build. Apple's native `NEAppRule` / per-app VPN path is treated as managed/MDM capability unless a later App Store-specific feasibility review proves a supported consumer design. Store UI must hide unsupported controls rather than emulate them inaccurately.
- **IDENTITY / HELPERS.** Application matching must survive ordinary app updates and handle helper/tool processes deliberately; matching must use stable application identity where possible rather than ephemeral PID-only rules.
- **SAFETY / RECOVERY.** A per-app implementation must preserve APL's ownership journal and rollback discipline, fail safely after crashes, sleep/wake and reboot, and never strand macOS networking or overwrite unrelated proxy/VPN state.
- **UX PARITY.** When supported, expose the same simple model used elsewhere: user picks applications to bypass the proxy, the list shows capability/state clearly, and changes apply through a controlled reconnect without surfacing low-level routing internals.

### APL-MAC-PERAPP staged delivery

1. **Stage A — feasibility / flow attribution:** on a Direct Developer ID test build, prove reliable source-application identification and a real split such as Safari **DIRECT** while another selected test application remains **PROXY** (and vice versa), including helper/tool process behavior.
2. **Stage B — recovery/security:** validate rule changes, disconnect/reconnect, forced runtime failure, sleep/wake, reboot, app update/removal, stale identity handling and exact rollback of APL-owned network state.
3. **Stage C — product UI:** add installed-application selection and exclusions UI aligned with Windows/Android, with capability-gated messaging for unsupported Store/managed contexts.
4. **Stage D — production Direct release:** sign/notarize the required app/system extension components, run physical macOS release acceptance, document uninstall/rollback, and ship only in a new Direct desktop release.
5. **Stage E — managed/MDM option:** if enterprise demand justifies it, add a separate managed `NEAppRule`/Per-App VPN configuration path. Do not conflate this with ordinary consumer App Store functionality.

**Release boundary:** this track is approved for the roadmap but is **not started** and is not part of published v0.2.16 or the current Mac App Store 0.2.17 build 3 review binary. It must not trigger a rebuild/resubmission of the Store candidate while Apple review is pending.

## 7D. International-traffic cost-aware routing — APL-TRAFFIC-001 — FUTURE / PRODUCT-APPROVED / RESEARCH

**Research trigger (2026-10-05):** Russian authorities and mobile operators are reported to be discussing possible charging for high-volume international traffic in 5G networks. Treat the reported **50 GB** threshold and the technical accounting model as provisional until an official rule, tariff methodology or operator implementation is published.

**Product objective:** make APL capable of choosing an economically efficient route without exposing routing complexity to the user. The capability must remain useful independently of any specific 5G charging rule.

- **MULTI-HOP ROUTING — NEW.** Support a provider-neutral chain such as `client -> RU ingress -> foreign exit -> destination`, with health, latency, capacity and price attributes for each hop.
- **COST-AWARE ROUTER — NEW.** Extend Smart Supplier Router so it can compare direct foreign proxy/VPN routes with composed ingress+exit routes and select by availability, quality, latency, price and policy.
- **DIRECT-RU SPLIT — RETAIN.** Russian destinations may remain DIRECT while selected foreign destinations/applications use the configured route; do not turn the whole product into an always-on full-tunnel requirement.
- **PROVIDER-OWNED INFRASTRUCTURE FIRST.** For marketplace design, prefer third-party RU ingress and foreign exit providers so APL remains software/router/marketplace rather than automatically becoming the operator of the transit infrastructure.
- **ARVECTUM-OWNED RU GATEWAY — LEGAL STOP-GATE.** Do not provision or publicly offer an Arvectum-owned Russian traffic gateway until communications/data-processing/licensing and traffic-responsibility implications are separately reviewed.
- **5G/LTE UX — CONDITIONAL.** If an enacted rule applies only to 5G, APL may show usage/context guidance and explain an OS-level LTE option where the platform permits it. Do not claim that APL can programmatically force radio mode on platforms that do not expose that capability.
- **REGULATORY INPUT, NOT EVASION.** Do not implement DPI camouflage, billing-counter manipulation, traffic misclassification or a feature marketed as tariff circumvention. Re-evaluate the route model against the exact official accounting definition before implementation.
- **MEASUREMENT BEFORE PRODUCTIZATION.** When rules become concrete, build a lab matrix across major operators: what endpoint is visible to the operator, how traffic is classified, whether roaming/IPv6/CDN/private relay paths differ, and whether RU-ingress traffic is actually accounted as domestic.
- **FAILOVER / SAFETY.** Multi-hop must degrade predictably: explicit route health, bounded reconnect, no secret leakage, deterministic rollback to the user's prior routing state, and no silent switch from a policy-constrained route to an unapproved one.

Staged delivery:
1. **Stage A — regulatory/technical research:** capture the official rule/methodology and operator implementation; determine exactly what is metered.
2. **Stage B — provider-neutral multi-hop core:** route graph, ingress/exit contracts, health/capacity/price metadata and deterministic selection.
3. **Stage C — lab validation:** real mobile-network measurements for DIRECT vs foreign exit vs RU-ingress→foreign-exit, including IPv4/IPv6 and 5G/LTE where available.
4. **Stage D — product UX:** simple route mode, usage/cost hints, diagnostics and explicit advanced details without protocol jargon in the primary flow.
5. **Stage E — marketplace composition:** supplier auction for ingress and exit capacity only after legal/commercial review and measured benefit.

**Execution boundary:** product-approved research track only. It is not added to the active execution queue and does not reactivate paused APL-NODE-001 or Arvectum Network infrastructure work.

## 8. Mobile applications

### Android — GitHub public 0.1.19 / current-main + RuStore candidate 0.1.38 (39)

- **GITHUB/GITVERSE PUBLIC BASELINE — android-v0.1.19.** This remains the latest published Android release in those channels until a separate publication task creates a later release.
- **CURRENT MAIN — 0.1.38 / versionCode 39.** PR #221 merged the combined RuStore source to main at `676a987105d8f01b8ed32db8b500b58a26e74542`.
- **PUBLIC FLAVOR — ADS ENABLED.** The public flavor includes Yandex Mobile Ads App Open integration using RuStore block `R-M-20130429-1`.
- **PRIVATE FLAVOR — AD-FREE.** A distinct private flavor/package identity is present in the same codebase and does not include the ad integration; separate private distribution remains a delivery concern, not a second divergent application.
- **NO FRIEND/FREE PROFILES IN THE PUBLIC APP.** PR #221 removed the friend/free gateway UX, `FreeGatewayClient`, free-session refresh/recovery behavior and obsolete persisted free selection from the Android public path.
- **CORE USER FEATURES RETAINED.** Manual user-supplied proxy profiles, Auto across user profiles, site exclusions, application exclusions, accepted adaptive UI fixes and VPN recovery behavior remain.
- **RUSTORE — SUBMITTED / WAITING FOR MODERATION.** Version 0.1.38 (39), package `ru.arvectum.proxylauncher`, production-signed APK SHA-256 `21519775dd098fba2c2389ced34e5e991bf3335b6a414af3561b298515f8d572`, audience 100%. Publication mode is **Manual after approval**.
- **HISTORICAL FREE-GATEWAY INFRA.** The prior RU/US friend-test gateway evidence is preserved as historical controlled-test infrastructure, but it is not part of the current public Android client path and must not be reintroduced without an explicit new product task.
- **NEXT GATE.** Wait for RuStore moderation. Any rejection remediation starts from current main; any later GitHub/GitVerse/site 0.1.38+ publication is a separate release task.

### iOS — App Store PUBLISHED: 0.1.38 build 42 (verified 2026-10-28)

- **LIVE STOREFRONT — 0.1.38 (42).** Apple public Lookup `id6816013574` confirms 0.1.38, published 2026-10-27, and developer website `https://arvectum.com/`. Previous 0.1.37 (41) is historical.
- **PUBLISHED 0.1.38 UX.** Includes selectable system/light/dark appearance; user-supplied proxy profiles, Auto/failover, site exclusions, iOS Shortcuts app automation. Apple App Store developer website and Support URL were changed to `arvectum.com` for ru/en-US as part of 0.1.38 review.
- **RСЯ `app-ads.txt` NEXT CHECK.** The canonical `https://arvectum.com/app-ads.txt` is reachable, and the Apple public developer website now correctly points to the same domain. Confirm actual Yandex RСЯ ownership verification status separately; do not mistake Apple link change for Yandex approval.
- **USER FEEDBACK P1 — iOS first connection and language clarity (2026-10-28).** A new peer review liked the minimal design and clear Connect button, but reported beginner confusion about proxy profile setup and language controls.
- **0.1.39 (43) RELEASE CANDIDATE — IN DEVELOPMENT.** Implemented optional three-page first-run guide explaining user-supplied proxy credentials and iOS VPN approval, re-openable via Settings → First Connection. Added contextual explanations for Host/Port/Type/Authentication in the profile editor, a visible Settings → App Language picker (System / Russian / English), and actual RU/EN Localizable.strings covering the main app UI, profile management, help, activity, privacy disclosure and error text. This is a separate product iteration, not yet publicly released.
- **TEST/RELEASE GATE.** Ensure RU/EN resources are packaged in application target and language selection is persisted, modal onboarding is skippable, iOS Release build + Swift tests + Xcode project/tests pass. No changes to PacketTunnel / proxy routing; no Yandex Mobile Ads SDK. GitHub CI and App Store next-version approval must be verified before calling 0.1.39 published.
- **PENDING LATER FEATURES.** Smart Exclusions (related-domain discovery), full-screen/real-device accessibility and localizations QA, wider proxy-profile input/import formats, privacy-gated ad monetization (issue #261). Don't mix Apple VPN 5.4 compliance review with this iOS onboarding update.

## 9. Currently available workstreams

1. **[Desktop release] v0.2.16 — PUBLISHED / IMMUTABLE.** Windows/Astra/RED OS/AppImage plus Developer ID-signed/notarized Apple Silicon + Intel DMGs.
2. **[Android / RuStore] 0.1.38 (39) — SUBMITTED / WAITING FOR MODERATION.** Public flavor has Yandex App Open ads and no friend/free profiles; private flavor is ad-free. RuStore publication is manual after approval.
3. **[iOS App Store] 0.1.38 (42) PUBLISHED / PUBLIC; 0.1.39 (43) ONBOARDING/LOCALIZATION CANDIDATE.** Apple public developer link is now arvectum.com. New feedback is being implemented as optional first-run guide and real RU/EN app language selection; public 0.1.38 remains unchanged.
4. **[macOS App Store] 0.2.19 build 8 — WAITING_FOR_REVIEW / MANUAL RELEASE.** Verified by owner on MacBook; public macOS Store version remains 0.2.17. Review submission received 2026-10-14; publication after Apple approval is a separate manual owner decision.
5. **[Per-app Windows enforcement] IMPLEMENTED / PHYSICAL PASS ON CURRENT MAIN.** Owner selected official signed WinDivert 2.2.2; PR #241 implementation and PR #243 installer fix are merged and physically validated. Custom WFP remains lab-only. Next gate is an explicit future Windows desktop release; published v0.2.16 is unchanged.
6. **[Windows trust / REVIEW] APL-REL-016 — READY FOR REFRESH.** Latest substantive PR #161 remains version-stale against v0.2.16; future native signing starts with a new release, never by mutating v0.2.16.
7. **[Rospatent / HUMAN] program registration package — PREPARED / WAITING FOR APPLICANT FACTS.** PR #181 tracks the checkpoint; official filing/signature remains human.
8. **[Russian Software Register / HUMAN] dossier prepared on exact v0.2.9; external filing remains on hold for real private/infrastructure/signature gates.**
9. **[Adaptive UI] APL-UI-001 — DONE / MERGED #193.** It remains the shared current UI baseline, not an active implementation task.
10. **[Product expansion / FUTURE] APL-CONNECT-001 — PRODUCT-APPROVED.** Universal connection input: ordinary proxy, VPN link/key/config, MTProto, QR/deep link, managed subscriptions and Marketplace zero-config delivery, staged so protocol complexity stays out of the default UX.
11. **[macOS per-app / FUTURE] APL-MAC-PERAPP — PRODUCT-APPROVED / NOT STARTED.** Primary target is a Direct Developer ID implementation with real source-app attribution and DIRECT/PROXY split routing; Mac App Store behavior remains capability-gated, with managed/MDM Per-App VPN treated separately.
12. **[Backlog-only] APL-NODE-001 and Arvectum Network remain intentionally absent from the primary roadmap and execution queue until explicit Owner reactivation.**
13. **[Smart Exclusions] APL-SMART-001..004 — OWNER-APPROVED / PLANNED AFTER 0.2.19 REVIEW.** WebKit dependency discovery and local graph first; dynamic Rust routing later, optional Safari extension last. Not present in build8; see section 6A.

### Repository-hygiene note

Open PRs #81/#103/#132/#157 are superseded Windows-trust preparation history; #161 is the latest substantive stale trust packet. Historical per-app recommendation PRs #68/#144 are superseded by the Owner-selected production WinDivert implementation in merged PR #241 and its physical-installer fix in merged PR #243. Historical rollback/RED OS/mobile closeout branches remain non-authoritative where later merged work exists. Backlog-only paused initiatives are intentionally omitted from this primary roadmap.

### Execution order

- Follow the canonical `.agent/current-task.yaml` for the active user-facing workflow.
- **Android / RuStore:** do not rebuild or resubmit merely because moderation is pending. On RuStore feedback, start a new remediation task from current main and the exact 0.1.38 (39) artifact/source evidence. After approval, publication remains an explicit manual release decision.
- **macOS App Store (2026-10-14):** 0.2.19 build 8 has been submitted for review, releaseType MANUAL; previous 0.2.17 is public and 0.2.18 was withdrawn. Wait for Apple, never auto-publish or change the submitted binary.
- **iOS App Store:** 0.1.38 (42) is published; 0.1.39 (43) onboarding and RU/EN localization is in development and must pass tests/review before publication.
- **APL-CONNECT-001:** product direction is approved; start with Stage A universal import/MTProto handoff when this workstream is explicitly prioritized, then VLESS+Reality as the first full-tunnel expansion.
- **APL-SMART-001..004:** planned for after macOS 0.2.19 review, not part of tested build 8.
- **APL-MAC-PERAPP:** product direction is approved but implementation is not started; first gate is a Direct Developer ID feasibility prototype proving source-app attribution plus real DIRECT/PROXY split routing. Keep the current Mac App Store build unchanged while it is under review.
- **Windows per-app:** production architecture is settled on official signed WinDivert 2.2.2 and physically accepted on current main. Do not revive the custom-WFP production path without a new Owner decision; do not publish/release the merged feature without a separate Windows release gate.
- **Next direct desktop release:** when prioritized, cut a new release from current main (never mutate v0.2.16), include the merged Windows WinDivert production path and mandatory macOS recovery fixes, rerun platform-specific physical acceptance, then publish as a new version.
- **APL-REL-016:** safe REVIEW refresh remains available when prioritized.
- **Registry/Rospatent:** prepare evidence/forms as authorized, but final external signing/submission remains HUMAN.
- Paused backlog-only initiatives must not consume engineering time until the Owner explicitly restores them to the primary roadmap.
- **Proxy Launcher Watchdog remains outside this roadmap update and must not be enabled or modified by this task.**

## 10. Platform / distribution matrix

| Platform / form | Current state | Next gate |
| --- | --- | --- |
| Windows installer | **PUBLISHED v0.2.16; current main also contains physically accepted WinDivert per-app routing** | Next explicit desktop release + physical release acceptance; Authenticode remains a separate trust track |
| Windows portable | **PUBLISHED v0.2.16; current main has later unreleased Windows routing work** | Next explicit desktop feature release; keep v0.2.16 immutable |
| Astra Linux .deb | **PUBLISHED v0.2.16 / PHYSICAL BASELINE PROVEN** | Rerun physical acceptance only for material platform/recovery or filing changes |
| RED OS .rpm | **PUBLISHED v0.2.16 / PHYSICAL BASELINE PROVEN** | Rerun physical acceptance only for material platform/recovery or filing changes |
| Linux AppImage | **PUBLISHED v0.2.16** | Maintain governed runtime/license/release parity |
| macOS .app / DMG | **PUBLISHED v0.2.16 / DEVELOPER ID + NOTARIZED** | Next direct release: mandatory recovery acceptance; APL-MAC-PERAPP may enter only after its Stage A/B feasibility and safety gates pass |
| macOS Mac App Store | **PUBLIC v0.2.17 / v0.2.19 (8) WAITING_FOR_REVIEW; MANUAL release** | Await Apple response and separate owner publication approval; Smart Exclusions in future sprint |
| Android | **GitHub/GitVerse 0.1.19 PUBLIC; current main + RuStore 0.1.38 (39) WAITING FOR MODERATION** | RuStore moderation -> explicit manual publication or targeted remediation; other channels require separate release task |
| iOS | **0.1.38 (42) PUBLISHED / PUBLIC** | **0.1.39 (43) CANDIDATE:** beginner guide, editor glossary and System/RU/EN language setting; build/test/App Review gates before release |

## Completion discipline

Do not substitute CI for physical App Control/Astra/РЕД ОС/mobile-device evidence, detached Russian release evidence for Microsoft native Windows publisher trust, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags or replace published release assets in place. A documentation-only commit does not create a new product candidate. Current operational references must resolve to `arvectum2/proxy-launcher`.
