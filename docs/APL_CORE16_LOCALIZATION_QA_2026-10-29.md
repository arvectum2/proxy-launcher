# APL · локализации Core-16 — нидерландский, индонезийский, турецкий

Дата: 29.10.2026. Дополнение к существующему PR #272 без изменения ревью Apple. Основа: `ad8d29ea0c498d7cf5920656dbe1b86ec3ff0bda`.

## Охват

- Полностью добавлены три языка из реестра `arvectum-tools/core/localization/portfolio-locales.json`: `nl` (Nederlands), `id` (Bahasa Indonesia) и `tr` (Türkçe). Приоритет выбран по продвинутости этих языков в корпусе Arvectum Tools Core.
- Каждый язык содержит **155 iOS + 104 Android + 193 desktop = 452** исходные пользовательские строки. Новая волна: **1356 строк**, весь APL теперь **16 × 452 = 7232** в трёх платформах. Технические идентификаторы, серверная сеть, PAC, no_proxy, Packet Tunnel и приватные конфигурации не изменялись.
- `mobile/ios/Resources/<locale>.lproj/Localizable.strings`, iOS language-picker `AppLanguage`, `AppL10n.supportedLanguage`, `mobile/android/app/src/main/res/values-nl|values-in|values-tr/strings.xml`, `desktop_i18n.py`, тесты и единственный glossary.
- В Android `values-in` — стандартный legacy Android-квалификатор индонезийского языка `id`. В iOS/desktop используется `id`. Значение `AppLanguage.indonesian = "id"` не конфликтует со свойством `Identifiable.id`.

## Редакторская корректура

- Проверено соответствие управляющих кнопок и инструкций, терминов proxy/proksi, host, port, VPN, доменных исключений, системных настроек, журналов, сохранения паролей, сообщений о восстановлении после некорректного завершения.
- После первичного полного перевода **54 длинных инструкции** (18 для каждого нового языка) переписаны с корректным смыслом на языке интерфейса. Дополнительно **21 критичное предупреждение desktop** (7 на каждый язык) вычитано вручную и приведено к безопасной формулировке, особенно network recovery, невозможность сохранения конфигурации и неприкосновенность чужих настроек.
- Добавлены 28 терминоединиц `nl`, `id`, `tr` в `localization/editorial-glossary.json`; названия кнопок восстановления соответствуют тексту инструкции; сохранены `HTTP`, `HTTPS`, `SOCKS5`, `PAC`, `Network Extension`, `Packet Tunnel`, домены и dynamic-format placeholders `%s`, `%1$s`, `%1$d`.
- Три UI-источника построены локально, без внешнего сервиса при запуске приложений. Русский и английский оригиналы и все предыдущие 13 переводов не переписаны.

## Уровень проверки и ограничения

- Структурное равенство ключей и форматирования: `tests/test_core12_localization.py`, `tests/test_core12_editorial_review.py`, `tests/test_core16_expansion.py`, `tests/test_persian_rtl_localization.py`.
- **Не утверждается независимая вычитка профессиональными редакторами-носителями** или приёмка iOS/Android/macOS на физических устройствах. Перед релизом отдельно проверяются переносы длинных текстов, произношение VoiceOver/TalkBack, названия Shortcuts actions на соответствующих локалях и региональные нюансы.
- Старые статусы Apple review, текущая публикация и метаданные App Store Connect не менялись. Watchdog не затрагивался. PR не сливать автоматически без отдельного поручения.

## Source verification (Mac mini)

- 19 scoped core/iOS/Android/desktop localization checks PASS (including Core-16 checks), separately under system NL, ID and TR.
- Full Python suite with `APL_UI_LANGUAGE=nl`: **1289 passed, 6 skipped, 3 known inherited Windows maintenance cases deselected, 113 subtests passed**.
- iOS unsigned UI-only arm64 Simulator build **BUILD SUCCEEDED**, **16** `.lproj` bundled; all 16 Apple `.strings` `plutil` checks and AppLocalization Swift typecheck PASS. Full signed PacketTunnel archive is not part of this check.
- Android Gradle JDK17: **BUILD SUCCESSFUL**, `compilePublicDebugKotlin`, `compilePrivateDebugKotlin`, `testPublicDebugUnitTest`, `testPrivateDebugUnitTest` (49 tasks executed).
- `git diff --check` and Python syntax compilation PASS.
