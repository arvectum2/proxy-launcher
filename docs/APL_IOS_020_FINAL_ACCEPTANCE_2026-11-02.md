# APL iOS 0.2.0 (48): итоговая исходниковая приёмка 02.11.2026

Каноническая ветка: `feat/ios-020-product-plan-20261101`, Draft PR #296. Функциональный хэш дерева `mobile/ios`: `a786dfe086309d6281e60266845c150ed0238d87`. Архив собран из `5ce33b9b65d602934afa6db4f6f04d08fc114528`; последующий `d02085ce` меняет только GitHub CI, не `mobile/ios`. Не отправлять в Apple без решения владельца.

## Успешные проверки

- Предыдущая ошибка сборки UI-test target устранена: `TunnelEngineHandoff.swift` включён также в `SmartExclusionsUITests` (XcodeGen и generated .pbxproj); целевой регрессионный Python unittest добавлен.
- Ошибочная проверка старого полного заголовка экрана исправлена на актуальный короткий «Исключения».
- На неподписанном Simulator тестовом профиле возникал Keychain/App Group startup crash; повторные сценарии выполнены **на подписанном Apple Development Simulator**, без изменения реальных профилей.
- Swift Core **104/104 PASS**, Python iOS 0.2 **42/42 PASS**, все 50 локализаций и 250 `.strings` plutil PASS, 0 отсутствующих ключей, 0 непереведённых English fallback и ошибок форматов.
- Подписанный iPhone 13 Simulator: Accessibility XXL de/ar Settings+Activity **1/1 PASS**; Exclusions accessibility audit **0 issues, 1/1 PASS**; Profile Library de/ar с синтетической `.invalid` записью **1/1 PASS**.
- Дополнительный подписанный Simulator UI: 10 языков `en/fr/de/ar/he/hi/ja/zh-Hant/am/ha`, экраны Settings/Import/Exclusions и короткие заголовки, **2/2 PASS (236,453 с)**.
- Изолированная компиляция Xcode Simulator `build-for-testing` **TEST BUILD SUCCEEDED**. В GitHub `Mobile iOS personal` добавлена проверка компиляции UI-target, а в Core job — все 42 iOS 0.2 Python contracts.
- Системный размер шрифта на QA Simulator возвращён в `large`, физический iPhone не изменяли.

## Новый подписанный артефакт

- Локальный `xcodebuild archive` **ARCHIVE SUCCEEDED** и `-exportArchive` **EXPORT SUCCEEDED**, только `destination=export`, без загрузки в Apple.
- IPA: `/Volumes/ArvectumSSD/Arvectum/releases/ios/0.2.0-48/final-source-5ce33b9b-20261102/exported/Arvectum Proxy Launcher.ipa` (8 593 292 байта).
- SHA256: `96c32d9935d59834fbbf2b7a77f843e0929a6868ab609e87f41fc2d2047ca8fe`.
- `codesign --verify --deep --strict` у приложения и PacketTunnel **PASS**; оба bundle ID и версии **0.2.0 (48)**, Team ID `VML75VY94V`; 50 `.lproj`, 1 PacketTunnel extension, Yandex SDK внутри; `unzip -tq` **PASS**.
- Ранее подписанные IPA из старых коммитов считать неактуальными. Новый артефакт не установлен на пользовательский iPhone.

## Внешние условия, пока не PASS

1. GitHub macOS runner: exact-code workflow `Mobile iOS personal` для коммита `d02085ce` (run `41410464336`) **QUEUED**, не объявлять зелёным. Локальный эквивалент сборки и тесты успешны.
2. Физический iPhone `iPhone Nikita` (UDID заканчивается `401E`) доступен, ранее установлен 0.2.0 (48), но не этот бинарник. Нужны явное согласование временного обновления на устройстве, восстановление исходных профилей/режима и два контролируемых работающих upstream-proxy с разными IP. Отдельно потребуется возможность безопасно симулировать отказ основного и восстановить его. Ни независимое сравнение IP двух провайдеров, ни реальный переход A→B→A на последнем коде не проведены; не выдавать за PASS.
3. VoiceOver **с реально включённым экранным диктором на физическом устройстве** не проверен. Simulator Accessibility Audit и XXL не подменяют эту приёмку. Нужны разрешение на изменение настроек VoiceOver и восстановление исходного состояния.
4. App Store/TestFlight и merge не разрешены, публикацию не выполнять. Конфиденциальность и рекламные параметры App Store не менять.
