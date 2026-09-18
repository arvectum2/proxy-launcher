# APL-REG-001F — pre-submission audit

Дата: 2026-09-18  
Регистрационный экземпляр: **0.2.9**  
Решение: **HOLD / технический dossier подготовлен, но обязательные HUMAN/PHYSICAL evidence ещё не подтверждены**.

## 1. Что уже готово

| Область | Статус | Основание |
|---|---|---|
| Наименование/версия/класс | READY | `v0.2.9`, класс 02.02 |
| Функциональное описание | READY | `APL_REG_001D_FUNCTIONAL_CHARACTERISTICS_RU.md` |
| Руководство установки/эксплуатации | READY | `APL_REG_001D_INSTALL_OPERATION_MANUAL_RU.md` |
| Support/maintenance narrative | READY FOR HUMAN FACTS | `APL_REG_001D_SUPPORT_MAINTENANCE_RU.md` |
| Infrastructure description template | READY; PHYSICAL EVIDENCE OPEN | `APL_REG_001D_TECHNICAL_INFRASTRUCTURE_RU.md` |
| License/price declaration | READY FOR HUMAN CONFIRM | MIT; no activation |
| Expert procedure | READY | `APL_REG_001D_EXPERT_TEST_PROCEDURE_RU.md` |
| Rule 1236 criterion map | READY | `APL_REG_001D_RULE_1236_COMPLIANCE_MATRIX_RU.md` |
| Windows 0.2.9 release | READY | current public release |
| Astra Linux physical compatibility | PROVEN on prior exact Linux release line | APL-LNX-010 |
| RED ОС physical compatibility | PROVEN on exact public 0.2.8 | APL-REG-001C / PR #83; 62/62 focused regressions |
| Public Russian mirror | READY as secondary evidence | GitVerse |

## 2. Current filing blockers

### G1 — правообладание и российский контроль заявителя: BLOCKED / HUMAN-LEGAL

Пункт 5 «а» требует принадлежности исключительного права допустимому российскому правообладателю и соответствующего контроля коммерческой организации. Exact-`v0.2.9` engineering/provenance packet подготовлен: source/tag tree, promoted package digests, provenance/SBOM и drift `v0.2.5 -> v0.2.9` reconciled. Репозиторий также хранит публичный receipt исполненного private decision от 2026-09-14, но он не заменяет проверку закрытого оригинала и не позволяет автоматически вывести охват творческих изменений после 2026-09-14. Перед подписью закрыть R-1A/R-1B/R-3 по `docs/APL_IP_001_V0_2_9_SIGNOFF.md` и приложить фактический закрытый corporate/IP bundle.

### G2 — иностранные выплаты: BLOCKED / PRIVATE-ACCOUNTING

Пункт 5 «в» ограничивает соответствующие выплаты иностранным лицам уровнем менее 30% профильной выручки за предыдущий календарный год. Нужны реальные бухгалтерские/договорные цифры и декларация; их нельзя выводить из dependency inventory.

### G3 — российская инфраструктура хранения/сборки/выпуска: BLOCKED / PHYSICAL

Пункты 5 «и» и «к» устанавливают территориальные/контрольные требования к техническим средствам. APL-REG-001B tooling готов, но необходимо реальное evidence российского authoritative source/object storage, build host и release/distribution perimeter. GitHub/GitHub Actions не считаются доказательством расположения в РФ; GitVerse mirror без подтверждения реального perimeter также недостаточен.

### G4 — поддержка/модификация и русский GUI: VERIFY / HUMAN+TECHNICAL

Нужно подтвердить фактическое российское лицо, выполняющее поддержку/модификацию исходного текста (п. 5 «з»), и проверить exact `v0.2.9` GUI на отсутствие обязательных пользовательских экранов/сообщений без русского языка (п. 5 «л»). Статический review exact `v0.2.9` подтверждает русскоязычные основные окна, действия и пояснения; при этом в диагностическом представлении остаются латинские технические/статусные токены (`PASS`, `WARN`, `FAIL`, `HTTP`, `SOCKS5`, `PAC`, `URL`, `no_proxy`). Поэтому финальный визуальный exact-release review сохраняется как явный gate, а не закрывается предположением.

### G5 — оборот в РФ и декларации: HUMAN CONFIRM

Публичная MIT-редакция и общедоступные release assets поддерживают техническую часть критерия, однако правообладатель должен подтвердить правомерное введение в гражданский оборот, отсутствие территориальных ограничений, отсутствие гостайны и достоверность всех сведений.

### G6 — корпоративные сведения, полномочия и УКЭП: BLOCKED / PRIVATE-HUMAN

Нужны актуальные корпоративные сведения, предусмотренные формой, контакты, полномочия подписанта (если требуются отдельным документом) и действующий квалифицированный сертификат электронной подписи.

### G7 — финальная сверка живой формы и действующего права: BLOCKED until filing session

Непосредственно перед подписью рабочий лист сверяется с `reestr.digital.gov.ru`, актуальной редакцией №1236 и текущими методическими рекомендациями.

## 3. Future-effective gate: trusted OS

### G8 — две доверенные ОС: NOT YET EFFECTIVE for class 02.02 on 2026-09-17

Пункт 5 «м» устанавливает совместимость минимум с двумя доверенными ОС, а постановление №1937 применяет это требование к классу «Программы обслуживания» с **2027-01-01**. Поэтому G8 не следует описывать как текущий filing blocker на 17.09.2026.

При этом продукт уже имеет физическую Astra + RED ОС базу. Для strongest evidence до 2027 рекомендуется выполнить короткий physical smoke exact public `v0.2.9` DEB/RPM и подтвердить актуальный правовой статус выбранных ОС как доверенных на дату проверки.

## 4. Что не является самостоятельным blocker

- отсутствие Authenticode у Windows 0.2.9 — документировано;
- историческая detached CryptoPro/Rutoken подпись 0.2.5 не переносится на 0.2.9 и не заявляется;
- внешний upstream proxy не является частью лицензии/поставки Proxy Launcher;
- продукт не SaaS и не требует Arvectum cloud control plane;
- exact `v0.2.9` Astra/RED smoke не является уже действующим требованием п. 5 «м» для класса 02.02 до 2027-01-01, хотя остаётся разумным future-proof evidence.

## 5. Filing decision

По публично подтверждённым данным репозитория нажимать «Подписать и отправить» пока нельзя: G1–G7 должны быть закрыты либо подтверждены уполномоченным владельцем реальными private/physical evidence. После этого audit меняется на `READY TO FILE`, а external submission выполняется только уполномоченным подписантом с УКЭП.
