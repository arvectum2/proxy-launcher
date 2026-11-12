# APL iOS 0.3.0 — приёмка через iPhone Mirroring, 12.11.2026

**Дополнение после 19:57 MSK:** Xcode XCTest внутри подписанного APL 0.3.0 подтвердил доступность всех **3/3 непустых Keychain-паролей** уже существующих прокси; никакие значения не копировались или выводились. Побайтовая неизменность трёх профилей после этого теста подтверждена. [Протокол Keychain](APL_IOS_030_IPHONE_KEYCHAIN_READONLY_2026-11-12.md).

**Актуальный статус после 19:39 MSK:** с разрешения владельца **подписанная Development Debug APL 0.3.0 (49) установлена поверх App Store 0.2.0 через Xcode CoreDevice**, без удаления контейнера, сброса Keychain или подключения VPN. Все три существующих профиля и ранее выбранный профиль сохранились. Пройдено 2 физических XCTest. Ранние формулировки ниже «не установлена» относятся к этапам **до** 19:27 и не отражают текущую версию на iPhone. App Store 0.3.0 **не опубликована**.


Физический iPhone 13, iOS 27.2.1, USB → Mac mini, Xcode 27.1, Developer Mode включён. iPhone Mirroring успешно подключён после первоначального timeout. Владелец разрешил физическую приёмку через Mirroring; рабочий VPN не переключать и действующую 0.2.0 не заменять до явного backup/install gate.

## Исходное состояние опубликованной 0.2.0

- [x] APL 0.2.0 запускается, реклама и экран Home видны.
- [x] В библиотеке три действующих профиля, выбран прежний профиль «Нидерланды 2»; персональные IP и секреты не копировались.
- [x] APL исходно отключён: кнопка «Подключиться».
- [x] Исключений 0; автоматическое расширение включено.
- [x] Язык «Русский» и системная тема сохранены.

## Физические UI-результаты без изменения рабочих данных

| Сценарий | Результат |
| --- | --- |
| Открыть APL через Mirroring, перейти на четыре основные вкладки | PASS: Home, Profiles, Settings доступны |
| Список профилей до и после QA | PASS: 3 профиля, без изменений |
| Ввести http://qa.invalid:1234 и нажать «Проверить» | PASS: preview одного HTTP-профиля, импорт отменён, не сохранён |
| Просмотреть исключения | PASS: пустой список, без изменения маршрутов |
| Открыть раздел «Копия» | PASS UI: требует пароль бэкапа не менее 12 символов. Бэкап не создан без выбора пароля владельцем |
| Открыть VPN Shortcuts | PASS UI: три действия доступны, не активировались |
| Пройти три страницы onboarding | PASS UI: профили/VPN не менялись |
| Переключить RU → EN → RU | PASS с дефектом: основная локализация меняется, язык возвращён |
| Проверить подписи тем после RU → EN | FAIL в 0.2.0: сегменты «Системная/Светлая/Тёмная» остаются русскими на английском Settings; regression UI test добавлен в 0.3.0 |

## Исправление по результатам физической приёмки — iOS 0.3.0

- [x] На физическом iPhone в опубликованной версии 0.2.0 после переключения RU → EN три подписи выбора темы оставались русскими, хотя остальные пункты Settings переводились.
- [x] В ветке QA для 0.3.0 добавлен явный `title(forLanguage: appLanguage)` и `AppL10n.tr(..., language:)` для кнопок темы; не зависит от задержки синхронизации @AppStorage.
- [x] XCTest `CompactSettingsUITests.testThemeSegmentsRelocalizeWithoutRestartingAppOrChangingAppearance` сначала принудительно выбирает русский через UI, затем английский и обратно; не использует launch-argument `-appLanguage.v1 ru`, подменяющий UserDefaults.
- [x] На iOS Simulator XCTest PASS 26.818 s (12.11.2026); выбранная тема сохранилась.
- [ ] Изменение пока **не установлено** на рабочий iPhone: физический регрессионный тест новой 0.3.0 ждёт безопасного обновления после резервной копии.

## Подписанный артефакт 0.3.0(49) — не установлен

- [x] На Mac mini выполнен signed Debug iPhoneOS arm64 build из main 1df919170e8e9e7949cfac4395f2ae74082fd5db, с override версии 0.3.0 и build 49. Build PASS.
- [x] Main app и PacketTunnel appex проходят codesign --verify --strict. Установлены APL Development и APL Packet Tunnel Development, устройство входит в ProvisionedDevices.
- [x] Application identifiers совпадают с App Store 0.2.0. Проверены Team, App Group, shared Keychain и Network Extension entitlements; CloudKit capability выключена.
- [x] App ~52 MB, PacketTunnel extension ~12 MB.
- [ ] Не устанавливался и не включал VPN. После исправления локализации Debug-кандидат нужно пересобрать заново.

## Оставшиеся обязательные испытания

- [ ] Разрешение владельца на backup и замену App Store 0.2.0 отдельным подписанным QA-кандидатом. В текущем signed build идентичный Bundle ID, значит установка может затронуть user profiles/Keychain. Нельзя удалять приложение и пользовательские секреты.
- [ ] Физическая миграция 0.2.0(48) → 0.3.0(49), проверка восстановления ID профилей, Keychain, настроек и rollback.
- [ ] Отдельный QA Xray/standard-WG PacketTunnel → external nonce egress, DNS/IPv4/IPv6/UDP, Wi-Fi/LTE и fail-closed. Native research lab пока не интегрирован в подписанный user build; «VLESS работает» не утверждается.
- [ ] Проверка QR-камеры непосредственно на iPhone (Mirroring не заменяет физический optical capture).
- [ ] CloudKit private entitlement и конфликт/opt-in на двух устройствах.
- [ ] Signed App Store 0.3.0 candidate и одно публичное обновление только после полного acceptance.

## Итог адресной регрессии после QA-исправления

- [x] Из теста смены языка убран принудительный `-appLanguage.v1 ru`: NSArgumentDomain имел приоритет над UI-сменой и давал ложные FAIL.
- [x] Реальный XCTest на iOS Simulator: RU → EN → RU, все три названия темы + выбранная тема, **PASS 26.818 s**.
- [x] Полная серия **310 Python-тестов, 1513 подтестов** и **226 Swift-тестов** PASS.
- [x] Повторный signed Debug iPhoneOS ARM64 candidate **0.3.0 (49)**: `xcodebuild BUILD SUCCEEDED`, main app + PacketTunnel strict signature verification PASS; signed main executable SHA256: `ea78c8bb6c61c52bf5c7e4da3b764a5f4b995353ced6553f97351c1c26f46262`.
- [ ] Подписанный Debug candidate **не установлен** на реальный iPhone: у основного приложения идентичный Bundle ID с 0.2.0. До установки необходима контролируемая резервная копия профилей и разрешение на замену приложения.

Результат: baseline iPhone 0.2.0 сохранён. Актуальная 0.3.0 пока НЕ установлена, НЕ принята и НЕ опубликована.

## Продолжение 12.11.2026, 17:26–17:35 MSK

- [x] iPhone13 снова сопряжён по USB и доступен через Mirroring; три исходных профиля 0.2.0 сохранены, VPN не менялся.
- [x] Открыта форма «Профили → Копия». Встроенный экспорт шифрует файл AES-GCM с PBKDF2-HMAC-SHA256 (210000 итераций) и требует пароль не менее 12 символов.
- [ ] Автоматическое заполнение двух SecureField через Mirroring оказалось ненадёжным. Файл НЕ создан. Форма закрыта без сохранения; временный Mac Keychain item удалён и буфер очищен.
- [ ] Требуется, чтобы владелец сам ввёл пароль дважды и сохранил .aplbackup в Files вне каталога APL; не передавать пароль в ChatGPT.
- [ ] Установка QA 0.3.0(49) поверх рабочей 0.2.0 возможна только после подтверждения копии и отдельного разрешения.

## Этап 19:27–19:39 MSK — контролируемое обновление через Xcode CoreDevice

| Проверка | Фактически установлено |
| --- | --- |
| Подписи и entitlement основного приложения и PacketTunnel | PASS: подписанный iPhoneOS Debug 0.3.0 (49), одинаковые Team/App Group/Keychain group, CloudKit OFF |
| iCloud Backup перед установкой | Включён; последняя подтверждённая резервная копия 12.11.2026 18:09:35 MSK. **Отдельный зашифрованный .aplbackup ещё не создан** |
| Способ установки | PASS: `xcrun devicectl device install app`, завершилось `exit 0`; **никакого uninstall/erase/reset** |
| Версия на iPhone | PASS: CoreDevice `ru.arvectum.proxylauncher.ios` — `0.3.0`, build `49` |
| Запуск через Xcode | PASS: `devicectl device process launch`, приложение реально запустилось, без активации VPN |
| Существующие профили | PASS: App Group `profiles.v1` содержит **ровно 3** уникальных профиля; выбранный ID по-прежнему принадлежит списку |
| Физический read-only XCTest | PASS: `PhysicalUpgradeReadOnlyUITests.testExistingThreeProfilesAreVisibleAfterInPlaceUpgrade`, **14.077 s**, 0 ошибок; UI показывает 3 сохранённых профиля и версию 0.3.0 |
| Исправление локализации на iPhone | PASS: `CompactSettingsUITests.testThemeSegmentsRelocalizeWithoutRestartingAppOrChangingAppearance`, **27.006 s**, 0 ошибок; RU → EN → RU, подписи темы актуализируются |
| Сохранность после двух XCTest | PASS: повторно прочитаны App Group preferences. Три ID, выбранный ID и байты `profiles.v1` **побайтно совпадают** со снимком сразу после установки |
| Следующее аппаратное испытание | NOT RUN: непосредственный read-only Keychain access probe, реальный VPN egress, DNS/IPv6/UDP/path switching, устройство с CloudKit |

QA-хранилище снимков App Group находится только на Mac mini в приватном каталоге `/Users/master/ArvectumSafe/backups/proxy-launcher/ios-profile-preflight-20261112` с ограниченными правами; оно содержит **метаданные**, а не полную резервную копию паролей из iOS Keychain. В пользовательские логи и PR не копировались идентификаторы, адреса, имена или секреты профилей.

**Важное ограничение:** успешный in-place install и сохранность App Group не доказывают, что все ранее сохранённые Keychain-пароли доступны или что новые протоколы VLESS/WireGuard работают. Эти проверки остаются открытыми; тестовый Debug-кандидат не является подписанным App Store релизом. Любой rollback/uninstall сейчас рискован без отдельного подтверждённого экспортного бэкапа.
