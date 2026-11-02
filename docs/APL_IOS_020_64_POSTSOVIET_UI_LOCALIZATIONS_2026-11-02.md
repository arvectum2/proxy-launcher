# APL iOS 0.2.0: 15 бывших союзных республик — расширение интерфейса до 64 языков

Дата работы: 02.11.2026. Каноническая ветка `feat/ios-020-product-plan-20261101`, Draft PR #296. Источник для новых строк: публичные UI-тексты приложения, без учётных данных пользователя. 0.1.41 по решению владельца продолжает проверку Apple; никаких Apple ASC writes/изменений текущей заявки, App Store метаданных, рекламных SDK или privacy-карточки в этой задаче.

## Матрица 15 республик / 15 языков интерфейса

| Республика | Основной локальный язык APL / BCP 47 | Состояние до задачи | После |
|---|---|---|---|
| Россия | Русский `ru` | Уже есть | Сохранён |
| Украина | Украинский `uk` | Уже есть | Сохранён |
| Беларусь | Белорусский `be` (кириллица) | Не было | Новый UI |
| Молдова | Румынский `ro` | Уже есть | Сохранён |
| Эстония | Эстонский `et` | Не было | Новый UI |
| Латвия | Латышский `lv` | Не было | Новый UI |
| Литва | Литовский `lt` | Не было | Новый UI |
| Грузия | Грузинский `ka` (мхедрули) | Не было | Новый UI |
| Армения | Армянский `hy` | Не было | Новый UI |
| Азербайджан | Азербайджанский `az` (латиница) | Не было | Новый UI |
| Казахстан | Казахский `kk` (кириллица) | Не было | Новый UI |
| Узбекистан | Узбекский `uz` (латиница) | Уже есть | Сохранён |
| Туркменистан | Туркменский `tk` (латиница) | Не было | Новый UI |
| Кыргызстан | Киргизский `ky` (кириллица) | Не было | Новый UI |
| Таджикистан | Таджикский `tg` (кириллица) | Не было | Новый UI |

Итог — **11 новых языков / 64 языка интерфейса**. На каждом новом языке полный комплект `Localizable` (155), `ProfileManagement` (101), `ProxyImport` (40), `SmartExclusions` (45), `QuickActions` (3), всего **344 ключа / язык** и **320 файлов `.strings`** в iOS. В системном выборе языка на iOS и меню внутри APL есть языки/нативные названия. Альтернативные письменности без готовых каталогов (например, `kk-Latn`, `az-Cyrl`, `tg-Arab`, `uz-Cyrl`) явно ограждены от ошибочного отображения не той письменности при автоопределении.

### Точность терминологии и редактура

- Начальные переводы выполнены **машинным переводом**, часть через Google Translate (закэшированные завершённые строки), остальные — локально через модель Google MADLAD-400 CT2 INT8 под лицензией **Apache-2.0** (не переносится в приложение). Переводились только открытые строки UI, а не частные прокси/Keychain/файлы пользователя.
- Критические идентификаторы `APL`, `iOS`, `VPN`, `SOCKS5`, `HTTP(S)`, `Network Extension`, `Packet Tunnel`, `Keychain`, `host:port`, протоколы URL, `gosuslugi.ru`, `gu-st.ru`, параметры формата `%d` и `%@` подвергнуты адресному аудиту. Нельзя подменять названия сетевых механизмов переводом похожих бытовых слов. Удаление профиля, failover, выбор прямого маршрута и исключения не должны менять смысл.
- Машинный перевод и технический аудит **не означают независимую вычитку носителем**. Редакторская вычитка 11 языков для пользовательской публикации остаётся отдельным quality gate, особенно малоресурсных `tk`, `tg`, `ky`, `ka`, `hy`. Все 64 UI языка не тождественны языкам App Store.

### Метаданные и публикация

Apple App Store Connect поддерживает **50** кодов локализаций метаданных (входящих в официальную таблицу Apple), у APL все они подготовлены после предыдущей задачи, с **100** реальными скриншотами; для новых 11 языков **не создавать вымышленные ASO-коды или 22 рекламных скриншота**. Apple показывает поддерживаемый fallback языка карточки магазина в конкретной географии, а после установки APL может показывать локальный язык из собственной `.lproj`. Это не доказывает, что продукт доступен во всех 15 странах — App Store availability является отдельной настройкой аккаунта. Источник: https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/ .

### Релизные ограничения

Ветка 0.2.0 остаётся Draft; номер приложения не менялся и подача в Apple не выполнялась. Старые IPA без 11 новых языков не подходят для будущего релиза; после редакторской приёмки и отдельного разрешения потребуется новый подписанный архив. Историю 0.1.41 и рекламную/privacy-карточку не изменять.

## Source acceptance and checks, 02.11.2026

- **64/64** in-app UI language resources, **320/320** `.strings` files, all five tables / 344 keys for each added `be, et, lv, lt, ka, hy, az, kk, tk, ky, tg`.
- XcodeGen regenerated native project; new locale identifiers are visible in the target's resource build graph. `swiftc -typecheck` of `AppLocalization.swift` PASS, all 64 ad disclosure labels are present and match the 64-code language manifest, no ad SDK behavior changed.
- **44/44 targeted Python tests PASS**, including language coverage, App Store mock/read-only constraints, localized copy, advertisement wiring, contextual safety text and 15-republic BCP47 mapping. **320/320 `plutil -lint` PASS**, full 64-locale `scripts/ios_020_locale_audit.py` PASS, `scripts/ios_active_release_preflight.py` PASS.
- Model output was intentionally reviewed for dangerous duplicate words and phrases, inverted meanings (especially “return to primary proxy”), `%d` counts, tech identifiers/URLs, and script character coverage. Curated corrections applied, no missing source keys or surviving English-language long-text placeholders according to source audits. **This is NOT independent native-speaker sign-off**, and translation naturalness must be reviewed before public release.
- Apple ASO remains 50/50 locale records with 100 screenshots; **no Apple API writes**, iOS 0.1.41 review untouched. Existing production iPhone user profiles/VPN, privacy declarations, Yandex Ads SDK, prior physical failover QA and Watchdog untouched.
- iOS Simulator Xcode build/package check: recorded in this task checkpoint after clean build completion; do not use an earlier Apple Distribution IPA to claim these 11 additional languages were shipped.
