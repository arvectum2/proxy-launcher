# APL Core-13: повторная вычитка существующих языков и فارسی (fa)

Дата: 29.10.2026. Ветка: `feat/apl-core12-locales-20261029`, дополнение к PR #272. Изменения относятся к *исходникам следующей версии*, а не к уже переданному в Apple бинарнику.

## Вторая редакторская волна

Повторно изучены инструкции для всех 12 исходных языков. Дополнительно исправлены 67 длинных строк iOS: два шага автоматизаций Shortcuts, терминология действий, единообразие языка в описаниях режимов подключения, настройка iPhone и системные темы. Исправления: ES 6, FR 7, DE 7, IT 7, PT-BR 7, PT-PT 7, JA 7, KO 7, ZH-Hans 6, ZH-Hant 6. Базовые RU и EN использованы как контроль смысла.

Наличие общих терминов, совпадение названий действий с кнопками, сохранение русских ключей и backend-протоколов дополнительно контролируются тестами первого прохода `tests/test_core12_editorial_review.py`.

## Persian (فارسی): новая тринадцатая локализация

Источник: 12-язычная базовая группа Arvectum Tools Core + отдельный `fa` из реестра `portfolio-locales.json` (tier 2; добавлен по прямому приоритету владельца). Региональный код `fa` поддерживает варианты `fa-IR`, `fa-AF` с применением одного корпуса.

Общий объём локализации: **155 iOS + 104 Android + 193 desktop = 452 строки**. Persian не является заглушкой английских значений. Выполнен базовый перевод всего корпуса; затем вручную отредактированы **147 из 155 iOS** и **102 из 104 Android** строк на предмет языка, технических терминов, состояния подключения, сети, VPN, разрешений и действий, плюс ключевые строки desktop. Значения `HTTP`, `HTTPS`, `SOCKS5`, `Network Extension`, `Packet Tunnel`, названия инфраструктуры и параметры формата оставлены неизменными.

RTL:

- iOS: `AppLanguage.fa`, отображение `فارسی`, поддержка `fa` из языкового выбора и системной локали, направление SwiftUI `.rightToLeft` при `fa`; `fa.lproj` включён в генерируемый проект Xcode.
- Android: `values-fa`, Android `supportsRtl=true`, строковый ресурс для имени приложения; нативное автоматическое направление Android зависит от локали устройства. Разделение сетевой логики и UI сохранено.
- macOS/Windows/Linux: `desktop_i18n` распознаёт `fa` и `fa-IR`, переменная тестирования `APL_UI_LANGUAGE=fa`; Tk-настройки выравнивают текст в подписях по правому краю. **Полное зеркальное перестроение сетки виджетов Tk не реализовано** и требует отдельного интерфейсного тестирования, это не эквивалент системного RTL SwiftUI/Android.

## Приёмка

- Ключи и форматные параметры `%s`, `%1$s`, `%1$d` для всех 13 языков сверяются тестами; 28 терминов сохраняют сквозные соответствия.
- `tests/test_persian_rtl_localization.py`: отдельные проверки охвата, подключения `fa`, RTL и терминов.
- iOS: требуется реальный тест длинных текстов, клавиатуры с персидской раскладкой и смешанных RTL/LTR строк на устройстве; авто-проверка UI-only не заменяет полноценную PacketTunnel-сборку.
- Android: требуется проверить системное направление на настоящем устройстве с локалью فارسی и смешанные поля IP/host:port.
- Desktop: проверить рендеринг персидских глифов и расположение подписи относительно поля на каждой ОС; текст выровнен RTL, геометрия не зеркалирована.

Проверки в GitHub CI после push следует оценивать по точному SHA новой ветки. При последующем релизе требуется отдельная приёмка визуальной локализации. Правила работы с сетями и исключениями не изменены.

## Проверенные результаты 29.10.2026

- 16/16 locale, terminology and Persian RTL source contract tests PASS.
- 1286 Python tests PASS, 6 skipped, 3 known inherited Windows maintenance tests deselected, 113 subtests PASS (APL_UI_LANGUAGE=fa).
- 13/13 Apple Localizable.strings resource plutil syntax PASS; Python syntax, git diff --check PASS.
- iOS unsigned UI-only arm64 Simulator build SUCCESS, 13 compiled localization bundles, Swift localization typecheck PASS. Full VPN PacketTunnel archive not claimed.
- Android XML and format placeholders pass cross-platform source tests. Full local Gradle build remained blocked by an unrelated hanging Gradle cache at an external-SSD symlink on the Mac mini; validate through GitHub CI before merging.
- Original macOS/Windows/Linux runtime routing and backend configuration untouched. Personal device Persian visual preview and full Tk grid mirroring remain a later acceptance gate.
