# APL-REG-001E — закрытый evidence checklist

Версия регистрационного экземпляра: **0.2.9**

**Не прикладывать сами закрытые документы к публичному GitHub.** Здесь только перечень.

| Evidence | Что проверить | Статус |
|---|---|---|
| Актуальные сведения ЕГРЮЛ ООО «Арвектум» | наименование, ОГРН, ИНН, адрес, руководитель | PRIVATE/HUMAN |
| Структура контроля | соответствие п. 5 «а» №1236 и данные, требуемые заявлением | PRIVATE/HUMAN |
| Полномочия подписанта | руководитель по ЕГРЮЛ либо действующая доверенность/МЧД, если требуется | PRIVATE/HUMAN |
| УКЭП | действующий квалифицированный сертификат уполномоченного подписанта | PRIVATE/HUMAN |
| Цепочка исключительного права | исполненный author/creator → ООО «Арвектум» документ, охватывающий submitted object | PRIVATE/HUMAN BLOCKER |
| Актуальный release scope | убедиться, что rights evidence охватывает код регистрационного экземпляра 0.2.9 | PRIVATE/HUMAN |
| Роспатент | фактический статус; не заявлять свидетельство без документа | PRIVATE/HUMAN |
| Иностранные выплаты | расчёт по п. 5 «в» за требуемый период, договорная/бухгалтерская опора | PRIVATE/ACCOUNTING BLOCKER |
| Оборот в РФ | подтверждение правомерного введения и отсутствия территориальных ограничений | PRIVATE/HUMAN |
| Российское лицо поддержки/модификации | организация/гражданин и реальная capability выполнять поддержку и изменение source | PRIVATE/HUMAN |
| Российский source/object storage | территория РФ, оператор/control, exact source/artifact lineage | PHYSICAL BLOCKER |
| Российский build host | территория РФ, toolchain/offline inputs, exact build record | PHYSICAL BLOCKER |
| Российский authoritative release/distribution | территория РФ, российский control, exact hashes | PHYSICAL BLOCKER |
| Русский GUI | протокол exact 0.2.9 user-facing review | TECHNICAL VERIFY |
| Экземпляр ПО | exact `v0.2.9` assets + `SHA256SUMS.txt` | READY technically |
| Astra Linux exact 0.2.9 protocol | OS/version + DEB SHA-256 + abbreviated physical protocol | RECOMMENDED before 2027 |
| RED ОС exact 0.2.9 protocol | OS/version + RPM SHA-256 + abbreviated physical protocol | RECOMMENDED before 2027 |
| Статус доверенных ОС | государственные записи выбранных exact ОС | FUTURE 2027 VERIFY |
| Цена/лицензионная модель | подтвердить, что MIT/без лицензионной платы соответствует фактам на дату подачи | HUMAN CONFIRM |
| Официальные контакты поддержки | e-mail/телефон, контролируемые правообладателем | PRIVATE/HUMAN |
| Финальная выгрузка заявления | сохранить подписанную версию и timestamp | AFTER SUBMIT |

## Правило закрытия

`READY TO FILE` допускается только когда текущие (не future-effective) критерии пункта 5 №1236 подтверждены, обязательные вложения п. 11 подготовлены, заявитель/подписант/УКЭП проверены, а live-form recheck выполнен. Future gate двух доверенных ОС ведётся отдельно с датой применения 2027-01-01 для класса 02.02.
