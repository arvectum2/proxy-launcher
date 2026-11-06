# Smart4 original native flow: absolute TTL fail-closed (offline)

**Дата:** 06.11.2026. **Task:** `APL-IOS-SMART4-TRACE-ABSOLUTE-TTL-20261106`.

## Дефект и реальное воспроизведение

DEBUG-only `Smart4OriginalFlowTrace` разрешает следить за native ID исходного TCP-потока ограниченное время (`lifetime=60s`). Однако `summary` и `expire` отсчитывали 60 секунд от **последнего** callback, а не от начала потока: после первого события T0 и заключительного payload в T+59 положительное диагностическое свидетельство считалось действующим вплоть до T+119. Аналогично callback в T+59 удерживал в bounded буфере 32 устаревших потока после T+60, препятствуя новым наблюдениям (`overflowed=true`). Два независимых XCTest до исправления воспроизвели **5 ошибок из 14 тестов**.

## Исправление

- Оба пути `summary(at:)` и `expire(at:)` теперь ограничивают поток **абсолютными 60 секундами от `Entry.started`**. Поздний пакет/подтверждение адресного семейства не продлевает разрешённое окно.
- При откате системного времени старое состояние сохраняется для уже существовавшего native ID, чтобы последовательность с `now < entry.last` оставалась неоднозначной и fail-closed, а не становилась новым ложноположительным потоком.
- Положительное доказательство в T+60 возможно только при полном наборе событий в пределах окна; после T+60 доказательство отсутствует. Просроченные потоки своевременно освобождают bounded capacity.
- Не затрагиваются правила DNS/IP, production маршрутизация, Native tun2proxy, Link/Keychain и реальные VPN-соединения. По-прежнему `externalEgressVerified=false`; Swift trace — **не** свидетельство независимого внешнего сервера.

## Проверки

- До исправления: новые тесты `testCompletedNativeFlowExpiresByFirstEventNotRecentPayload` и `testManyRecentCallbacksCannotKeepExpiredNativeFlowCapacityOccupied` **FAIL (5 assertions)**.
- После: focused **14/14 XCTest PASS**, Python source contract PASS; полный Swift Core **197/197 PASS** и iOS Python **212 (1 skipped), 0 failures**. unsigned ARM64 iPhoneOS **Debug/Release** и iOS Simulator App+PacketTunnel: **3/3 xcodebuild exit 0**. Имеются ранее известные предупреждения Sendable (Swift 6); GitHub CI независим от этой локальной проверки.

## Внешний аппаратный gate

Smart4 2b.2 `APL-IOS-SMART4-PHYSICAL-EGRESS-20261105` **остаётся blocked**. Никакой original captured PacketTunnel flow не сопоставлялся с независимым внешним DIRECT/PROXY nonce receipt. iPhone, пользовательский VPN, Keychain, App Store 0.2.0 и черновик PR #314 не трогали.
