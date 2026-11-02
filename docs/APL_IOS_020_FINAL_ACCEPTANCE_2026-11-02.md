# Текущий финальный source candidate — после DNS merge (02.11.2026)

**Эта запись имеет приоритет над более ранними фактами и путями к IPA ниже.** Источники iOS были изменены в `31d5cdc5` (DNS recovery, socket pressure, TLS relay) после того, как CI `41412264592` завершился успешно для старого дерева. Новое дерево `mobile/ios`: `ee4d247944aff9d6c97a9ce146f23768c1f1e1ff`. Последний проверенный source checkout commit `9775879a` (включает merge), архивация начата с текущего дерева.

- Swift Core **106/106 PASS**, Python iOS 0.2 **44/44 PASS** после merge; ранее 5/5 подписанных Simulator UI тестов PASS (UI/локализации в merge не затронуты), 50 языков.
- Архив: `/Volumes/ArvectumSSD/Arvectum/releases/ios/0.2.0-48/final-source-b8650a77-20261102/APL-0.2.0-48.xcarchive`. IPA: `/Volumes/ArvectumSSD/Arvectum/releases/ios/0.2.0-48/final-source-b8650a77-20261102/exported/Arvectum Proxy Launcher.ipa`. `ARCHIVE SUCCEEDED`, `EXPORT SUCCEEDED`, app/PacketTunnel codesign PASS, идентификаторы и версии 0.2.0 (48), 50 языков, ZIP PASS. SHA256 `afa930e1542d1d758f64ea47b1fa66cddc37e42cfe346588b7cd462a2cb409d7`.
- **Текущий GitHub CI не считать зелёным до подтверждения:** Mobile iOS personal run `41413811197` для нового кода QUEUED на macOS runner. Предыдущий run `41412264592` PASS 3/3 относится к старому исходному дереву `2a1e4e9c...`, не к DNS merge.
- Физические egress/Auto failover A→B→A и VoiceOver на iPhone не проводились на последнем бинарнике; требуется разрешение на in-place install/временную смену VPN и VoiceOver и пара контролируемых рабочих прокси. Исходные настройки/профили должны быть восстановлены. App Store, TestFlight, main и Apple privacy/ads не изменены.

---

# Финальное дополнение — iOS 0.2.0, 02.11.2026

**Этот раздел заменяет предыдущие сведения ниже о QUEUED CI и старом IPA `5ce33b9b`.**

- Канонический source commit: `6b38f6a355bb0d804adf7ca0c33cdc6026a72d56`; дерево `mobile/ios`: `2a1e4e9c28768a77f9761cad4d69ec42fba9c772`.
- GitHub Mobile iOS personal CI [run 41412264592](https://github.com/arvectum2/proxy-launcher/actions/runs/41412264592) **COMPLETED SUCCESS 3/3**: Core, unsigned-device (включая UI-target Simulator build-for-testing), unsigned-release. Ранее падавший job устранён: `fetch_tun2proxy.py --with-simulator` собирает отдельный патченный Rust ARM64 Simulator slice с закреплённой версией Rust/source/patch. Локальный полный pinned XCFramework и unsigned Simulator `TEST BUILD SUCCEEDED`. 2 новых теста; Python iOS **44/44 PASS**.
- **Новый и единственный актуальный подписанный IPA:** `/Volumes/ArvectumSSD/Arvectum/releases/ios/0.2.0-48/final-source-6b38f6a3-20261102/exported/Arvectum Proxy Launcher.ipa`; SHA256 `a775f666d3e3886a56b7db6d07aa9426ac4fddd617475500b0a7ab190949830b`. `ARCHIVE SUCCEEDED` и `EXPORT SUCCEEDED`, извлечение ZIP PASS, `codesign --verify --deep --strict` PASS для app и PacketTunnel, обе цели `0.2.0 (48)`, Team `VML75VY94V`, 50 `.lproj`, Yandex SDK встроен.
- Осталось до физического релизного допуска: A→B→A отказ/возврат VPN между двумя известными рабочими прокси, сверка egress с двумя независимыми HTTPS-сервисами, восстановление исходного состояния и реальная проверка VoiceOver на iPhone. На устройстве установлена **старая сборка с тем же номером 0.2.0 (48)**. Потребуются отдельное согласие на in-place update и временное изменение VPN/VoiceOver; пользовательские профили и Apple Connect сейчас не трогали.
- Draft PR #296 не слит, IPA не отправлялась в TestFlight/App Store. Конфиденциальность и реклама Apple оставлены без изменений.

---

# APL iOS 0.2.0 (48): итоговая исходниковая приёмка 02.11.2026

Каноническая ветка: `feat/ios-020-product-plan-20261101`, Draft PR #296. Текущее дерево `mobile/ios`: `2a1e4e9c28768a77f9761cad4d69ec42fba9c772`. Окончательный подписанный архив собран из `6b38f6a355bb0d804adf7ca0c33cdc6026a72d56`, дерево iOS `2a1e4e9c28768a77f9761cad4d69ec42fba9c772`. Предыдущий IPA заменён новым. Не отправлять в Apple без решения владельца.

## Успешные проверки

- Предыдущая ошибка сборки UI-test target устранена: `TunnelEngineHandoff.swift` включён также в `SmartExclusionsUITests` (XcodeGen и generated .pbxproj); целевой регрессионный Python unittest добавлен.
- Ошибочная проверка старого полного заголовка экрана исправлена на актуальный короткий «Исключения».
- На неподписанном Simulator тестовом профиле возникал Keychain/App Group startup crash; повторные сценарии выполнены **на подписанном Apple Development Simulator**, без изменения реальных профилей.
- Swift Core **104/104 PASS**, Python iOS 0.2 **44/44 PASS**, все 50 локализаций и 250 `.strings` plutil PASS, 0 отсутствующих ключей, 0 непереведённых English fallback и ошибок форматов.
- Подписанный iPhone 13 Simulator: Accessibility XXL de/ar Settings+Activity **1/1 PASS**; Exclusions accessibility audit **0 issues, 1/1 PASS**; Profile Library de/ar с синтетической `.invalid` записью **1/1 PASS**.
- Дополнительный подписанный Simulator UI: 10 языков `en/fr/de/ar/he/hi/ja/zh-Hant/am/ha`, экраны Settings/Import/Exclusions и короткие заголовки, **2/2 PASS (236,453 с)**.
- Изолированная компиляция Xcode Simulator `build-for-testing` **TEST BUILD SUCCEEDED**. В GitHub `Mobile iOS personal` добавлена проверка компиляции UI-target, а в Core job — все 44 iOS 0.2 Python contracts.
- Системный размер шрифта на QA Simulator возвращён в `large`, физический iPhone не изменяли.

## Новый подписанный артефакт

- Локальный `xcodebuild archive` **ARCHIVE SUCCEEDED** и `-exportArchive` **EXPORT SUCCEEDED**, только `destination=export`, без загрузки в Apple.
- IPA: `/Volumes/ArvectumSSD/Arvectum/releases/ios/0.2.0-48/final-source-6b38f6a3-20261102/exported/Arvectum Proxy Launcher.ipa` (8 606 227 байта).
- SHA256: `a775f666d3e3886a56b7db6d07aa9426ac4fddd617475500b0a7ab190949830b`.
- `codesign --verify --deep --strict` у приложения и PacketTunnel **PASS**; оба bundle ID и версии **0.2.0 (48)**, Team ID `VML75VY94V`; 50 `.lproj`, 1 PacketTunnel extension, Yandex SDK внутри; `unzip -tq` **PASS**.
- Ранее подписанные IPA из старых коммитов считать неактуальными. Новый артефакт не установлен на пользовательский iPhone.

## Внешние условия, пока не PASS

1. GitHub Mobile iOS personal [run 41412264592](https://github.com/arvectum2/proxy-launcher/actions/runs/41412264592) для коммита `6b38f6a3`: **3/3 jobs SUCCESS** — Core, Debug iPhone + Simulator UI target, Release iPhone. Предыдущий CI-провал из-за отсутствия Simulator-среза устранён. **CI больше не блокирует релиз.**
2. Физический iPhone `iPhone Nikita` (UDID заканчивается `401E`) доступен, ранее установлен 0.2.0 (48), но не этот бинарник. Нужны явное согласование временного обновления на устройстве, восстановление исходных профилей/режима и два контролируемых работающих upstream-proxy с разными IP. Отдельно потребуется возможность безопасно симулировать отказ основного и восстановить его. Ни независимое сравнение IP двух провайдеров, ни реальный переход A→B→A на последнем коде не проведены; не выдавать за PASS.
3. VoiceOver **с реально включённым экранным диктором на физическом устройстве** не проверен. Simulator Accessibility Audit и XXL не подменяют эту приёмку. Нужны разрешение на изменение настроек VoiceOver и восстановление исходного состояния.
4. App Store/TestFlight и merge не разрешены, публикацию не выполнять. Конфиденциальность и рекламные параметры App Store не менять.

## Финальные проверки после исправления CI

- Rust 1.98.1, закреплённый upstream коммит `e271de19`: оба среза `ios-arm64` и `ios-arm64-simulator` собраны с патчами, их хэши и XCFramework manifest проверены.
- **44/44** Python iOS 0.2 (включая 2 новых теста сборщика), **104/104** Swift Core; локальный ARM64 Simulator `build-for-testing` PASS, hosted GitHub 3/3 SUCCESS.
- Финальный подписанный архив+IPA с источника `6b38f6a3`, обе подписи, обе версии 0.2.0 (48), 50 `.lproj`, ZIP целостность PASS. Экспорт только в файл.
- **Открыто только**: разрешённая аппаратная приёмка двух прокси A→B→A, независимый внешний IP и VoiceOver на физическом iPhone. Не запускалось; Apple upload/merge не выполнялись.
