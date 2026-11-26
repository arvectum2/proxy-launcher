# Tasks — source conservation and release acceptance mapping

These are new integration tasks, not replacement APL product IDs. All remain open until verified.

- [ ] APL-SDD-T01 (R01) Verify the six source pins and inventory all native IDs, unchecked/exception markers, tables and unmarked requirements; identify historical/paused rather than discard.
- [ ] APL-SDD-T02 (R02) Map each scoped capability and original release criterion to existing tasks and exact candidate build evidence; resolve duplicated references.
- [ ] APL-SDD-T03 (R03) Reconcile physical upgrade, Keychain/profiles/backup and latest QA evidence; retain missing checks.
- [ ] APL-SDD-T04 (R04) Reconcile current physical network evidence, including upstream restrictions and independence of Smart4 acceptance. Keep unsupported features off.
- [ ] APL-SDD-T05 (R05) Review release, privacy/entitlement, authorization and actual publication boundaries; do not claim acceptance or publish.
- [ ] APL-SDD-T06 (R01–R05) Compare all source anchors and criterion evidence; retain changes with reviewed dispositions, then supply source links for Mission Control.


## Original release criteria — individual verification tasks

Every task below is open; partial report evidence does not complete a criterion. Existing roadmap scope and checks remain unchanged.

- [ ] APL-VERIFY-009 (APL-REL-009) Импорт, QR/Share: Физический импорт/backup на 09c6cdfe зафиксирован; полный QR/Share и подписанная итоговая сборка не подтверждены.
- [ ] APL-VERIFY-010 (APL-REL-010) Безопасные ошибки и исключения: Структурные регрессии и часть fail-closed проверок описаны; проверка финального артефакта и приватности открыта.
- [ ] APL-VERIFY-011 (APL-REL-011) HTTPS-загрузка списка: Main содержит исходную реализацию; точная физическая приёмка финального кандидата не установлена.
- [ ] APL-VERIFY-012 (APL-REL-012) Сохранённые подписки: Исходный Keychain-контракт не доказывает физическую приёмку токенов подписок и ручного обновления.
- [ ] APL-VERIFY-013 (APL-REL-013) CloudKit: Entitlement выключен; необходимы реальный private container, opt-in и два устройства.
- [ ] APL-VERIFY-014 (APL-REL-014) VLESS/Reality: Есть ранние ограниченные лабораторные результаты и восстановление тестового сервера; полный native physical egress финального артефакта открыт.
- [ ] APL-VERIFY-015 (APL-REL-015) WireGuard/AmneziaWG: Проверки тестовых серверов и прежних изолированных fixtures ограничены конкретными сборками; финальный physical underlay/egress и лицензии открыты.
- [ ] APL-VERIFY-016 (APL-REL-016) Smart Routing 4.0: Независимый настоящий native network policy/route acceptance открыт; legacy результаты не покрывают новый runtime.
- [ ] APL-VERIFY-017 (APL-REL-017) Native FIN/CLOSE_WAIT: Нужен отдельный физический протокол для исходного draft PR #314; подтверждения по этому критерию не установлены.
- [ ] APL-VERIFY-033 (APL-REL-033) Один подписанный IPA: Отчет сверки точного подписанного IPA 0.3.0(49) не устанавливает готовность всех функций или полный содержащий native Release.
- [ ] APL-VERIFY-034 (APL-REL-034) Непрерывное обновление: 19 ноября backup/restore и очистка тестовых данных приняты для установленного 09c6cdfe; полный upgrade и миграция финального IPA остаются открыты.
- [ ] APL-VERIFY-035 (APL-REL-035) Физический egress: Legacy egress принят в ограниченных протоколах; новые native transport, Wi-Fi/LTE и DNS не покрыты целиком.
- [ ] APL-VERIFY-036 (APL-REL-036) Регрессии, локализация, privacy: Отчёт 17 ноября: 64 директории и 322 strings, новая UI-локализация не установлена; ad SDK решение и containing Release открыты.
- [ ] APL-VERIFY-037 (APL-REL-037) Решение о релизе: Нет установленного решения собственника о точном финальном SHA/IPA и составе релиза. Не считать draft решением.
- [ ] APL-VERIFY-038 (APL-REL-038) Один публичный выпуск: Публичный 0.3.0 не подтвержден этими источниками. Нужны прохождение гейтов и отдельное разрешение на публикацию.
