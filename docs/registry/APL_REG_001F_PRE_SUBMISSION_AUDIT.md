# APL-REG-001F — pre-submission audit

Дата: 2026-09-17  
Решение: **HOLD / пакет технически подготовлен, внешняя подача пока заблокирована**.

## 1. Что уже готово

| Область | Статус | Основание |
|---|---|---|
| Наименование/версия/класс | READY | `v0.2.9`, класс 02.02 по APL-REG-001A |
| Функциональное описание | READY | `APL_REG_001D_FUNCTIONAL_CHARACTERISTICS_RU.md` |
| Руководство установки/эксплуатации | READY | `APL_REG_001D_INSTALL_OPERATION_MANUAL_RU.md` |
| Support/maintenance narrative | READY | `APL_REG_001D_SUPPORT_MAINTENANCE_RU.md` |
| License/price working declaration | READY FOR HUMAN CONFIRM | MIT; no activation |
| Экспертная процедура | READY | `APL_REG_001D_EXPERT_TEST_PROCEDURE_RU.md` |
| Windows 0.2.9 release | READY | current public release line |
| Astra Linux physical compatibility | TECHNICALLY PROVEN on prior exact Linux release line | APL-LNX-010 / PR #62/#69 |
| RED ОС physical compatibility | TECHNICALLY PROVEN on exact public 0.2.8 | APL-REG-001C / PR #83 |
| RED ОС focused regression evidence | READY | 62/62 PASS in APL-REG-001C closeout |
| Public release mirror | READY as secondary channel | GitVerse release mirror |

## 2. Блокеры до подачи

### G1 — исключительное право: BLOCKED

Нужен исполненный закрытый правоустанавливающий документ, однозначно подтверждающий переход/принадлежность исключительного права ООО «Арвектум» и охватывающий актуальный `v0.2.9` scope. Repository copyright/MIT сами по себе недостаточны.

### G2 — российский lifecycle perimeter: BLOCKED

`APL-REG-001B` описывает целевой sovereign lifecycle, но физическое evidence source/build/storage/distribution perimeter должно быть собрано владельцем. Нельзя подменять его GitHub Actions или одной ссылкой на GitVerse.

### G3 — exact registration-release Linux evidence: BLOCKED

`v0.2.9` изменяет Windows и сохраняет Linux-поведение `v0.2.8` без изменений. Тем не менее регистрационный экземпляр — `v0.2.9`; поэтому предпочтительно физически прогнать exact public `v0.2.9` DEB на Astra и RPM на RED ОС и записать SHA-256/результаты.

### G4 — актуальный статус доверенных ОС: LEGAL VERIFY

Техническая совместимость и правовой статус «операционная система, соответствующая требованиям к доверенному ПО» — разные факты. На дату подачи проверить актуальные государственные записи выбранных Astra/RED ОС и приложить требуемые документы/ссылки.

Для класса 02.02 изменения постановления №1937 устанавливают применение требования совместимости минимум с двумя доверенными ОС с **1 января 2027 года**. Если решение по заявке может выйти после этой даты или заявитель хочет сразу future-proof запись, G3/G4 закрываются до подачи.

### G5 — корпоративные сведения и УКЭП: BLOCKED / HUMAN

В закрытом bundle требуются фактические реквизиты, полномочия подписанта, контакты и действующая УКЭП. Они не должны генерироваться или публиковаться этим репозиторием.

### G6 — финальная сверка живой формы: BLOCKED until filing session

Поля/валидации портала могут измениться. Непосредственно перед подписью рабочий лист сверяется с `reestr.digital.gov.ru` и действующей редакцией постановления №1236.

## 3. Что не является блокером само по себе

- отсутствие Authenticode у Windows 0.2.9 — документировано, защиту Windows отключать не требуется;
- отсутствие переноса исторической detached CryptoPro/Rutoken подписи 0.2.5 на 0.2.9 — не маскируется и не заявляется;
- внешний upstream proxy — не часть лицензии/поставки ПО;
- отсутствие SaaS/control plane — продукт локальный.

## 4. Filing decision

Текущий ответ на вопрос «можно ли сейчас нажимать Подписать и отправить?» — **нет**.

Техническая документация APL-REG-001D готова для заполнения заявки. Для смены статуса на `READY TO FILE` необходимо закрыть G1, G2, G3/G4 в выбранной правовой стратегии и G5, после чего выполнить G6 и повторить этот audit.
