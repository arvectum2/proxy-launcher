# Пакет заявки в Единый реестр российского ПО

Статус: **PRE-SUBMISSION / не подписывать до закрытия HUMAN/PHYSICAL gates**  
Продукт: **Arvectum Proxy Launcher**  
Версия-кандидат: **0.2.9** (`v0.2.9`)  
Основной класс: **02.02 — Программы обслуживания**  
Заявляемый правообладатель: **ООО «Арвектум»**; юридическое основание исключительного права и корпоративные критерии подтверждаются закрытым пакетом до подачи.

## Назначение каталога

Каталог отделяет воспроизводимую техническую часть заявления от закрытых корпоративных документов. В публичный репозиторий не должны попадать персональные данные, доверенности, УКЭП/ключевой материал, подписанные правоустанавливающие документы, банковские сведения и иные закрытые доказательства.

Нормативный baseline: 2026-09-17, постановление Правительства РФ №1236 в действующей редакции и изменения постановления №1937 от 28.11.2025. Перед фактической подписью пакет ещё раз сверяется с живой формой ФГИС «Реестры ПО».

## Состав

- `APL_REG_001D_APPLICATION_WORKSHEET_RU.md` — карта полей заявления и готовых ответов.
- `APL_REG_001D_RULE_1236_COMPLIANCE_MATRIX_RU.md` — матрица критериев пункта 5 №1236.
- `APL_REG_001D_FUNCTIONAL_CHARACTERISTICS_RU.md` — функциональные характеристики и границы продукта.
- `APL_REG_001D_INSTALL_OPERATION_MANUAL_RU.md` — установка, эксплуатация, удаление и восстановление.
- `APL_REG_001D_SUPPORT_MAINTENANCE_RU.md` — сопровождение и жизненный цикл.
- `APL_REG_001D_TECHNICAL_INFRASTRUCTURE_RU.md` — хранение исходников/объектного кода, сборка, выпуск и распространение.
- `APL_REG_001D_LICENSE_PRICE_RU.md` — лицензирование, цена, внешние сервисы.
- `APL_REG_001D_EXPERT_TEST_PROCEDURE_RU.md` — процедура проверки для эксперта.
- `APL_REG_001E_PRIVATE_EVIDENCE_CHECKLIST.md` — перечень закрытых доказательств.
- `APL_REG_001F_PRE_SUBMISSION_AUDIT.md` — финальный gap audit.

## Публичные технические источники

- canonical source/release: `https://github.com/arvectum2/proxy-launcher`;
- релиз: `https://github.com/arvectum2/proxy-launcher/releases/tag/v0.2.9`;
- российское зеркало: `https://gitverse.ru/arvectum/proxy-launcher/releases`;
- контроль целостности: `SHA256SUMS.txt`;
- классификация: `APL-REG-001A_SOFTWARE_CLASSIFICATION_DECISION.md`;
- sovereign lifecycle: `APL-REG-001B_SOVEREIGN_LIFECYCLE.md`;
- RED ОС acceptance: `docs/APL_REG_001C_RED_OS_ACCEPTANCE.md`;
- Astra Linux acceptance: линия `APL-LNX-010`.

## Критический infrastructure gate

Пункт 5 №1236 требует, чтобы технические средства хранения исходного и объектного кода и компиляции находились в РФ, а средства выпуска/распространения/лицензирования — находились в РФ и контролировались российскими лицами. APL-REG-001B подготовил tooling/contract, но filing-grade физическое evidence ещё должно быть подтверждено. Публичный GitHub и само наличие GitVerse mirror не подменяют это доказательство.

## Trusted-OS timing

Для класса «Программы обслуживания» требование совместимости минимум с двумя доверенными ОС применяется с **1 января 2027 года**. На baseline 2026-09-17 это ещё не текущий filing gate класса 02.02, но это близкий lifecycle gate. Совместимость с Astra Linux SE и RED ОС уже физически проверялась на Linux-линии продукта; exact public `v0.2.9` DEB/RPM smoke остаётся предпочтительным future-proof evidence.

## Version gate

RED ОС physical acceptance было закрыто на exact public `v0.2.8`; `v0.2.9` изменил Windows rollback/recovery и release notes фиксируют неизменное Linux-поведение. Пакет не выдаёт это за physical exact-0.2.9 run.

До 2027 revalidation предпочтительно прогнать точные публичные `v0.2.9` DEB/RPM на Astra Linux SE и RED ОС и сохранить OS version + package SHA-256 + PASS/FAIL protocol.
