# APL iOS 0.3.0 — pinned native Xray provenance / offline supply-chain gate

Дата 12.11.2026. **Это инвентаризация и проверка происхождения, не полный SBOM и не разрешение на распространение чужого бинарника.**

| Проверяемое поле | Фактический результат |
| --- | --- |
| Upstream | `XTLS/libXray` |
| Версия, объект аннотированного тега | `v26.11.9`, `71d9d443aa88ff939ab6ce22b82aa4b2adcc4d9f` |
| Фактический исходный commit (peeled tag) | `5a0f7d8d1c28b34afb5727b04b26a10f6dbac7e3` |
| Apple CGO asset | `libxray-apple-cgo.zip` |
| SHA-256 (сверен с release asset) | `7c58346709f1856782a48d8f9926fb815c8ad1bbaf9e5d9dec4ee0cd1f41ed6f` |
| Закреплённый `go.mod` SHA-256 | `6cae0b0bb7f8fb6718b7e357ce28103161949c803901f7233bd9a8a862f56b02` |
| Xray-core transitive module | `github.com/xtls/xray-core v1.260327.1-0.20261109052709-676eaf66f8f0` |
| Go toolchain по upstream | `go 1.27.3`, установлен из проверенного официального архива в отдельный R&D каталог 15.11 |
| `go.mod` dependency entries | 60 |
| Файлов в ZIP | 28 (включая iOS-arm64 и iOS-Simulator arm64/x86_64 static libraries) |
| Исходный файл лицензии libXray | MIT |
| Исходный файл лицензии Xray-core | MPL 2.0 |

Результаты получены из оригинального GitHub release/источников и проверены локально в R&D каталоге. Ссылки: https://github.com/XTLS/libXray/releases/tag/v26.11.9 , https://github.com/XTLS/libXray/blob/v26.11.9/go.mod , https://github.com/XTLS/Xray-core/blob/main/LICENSE .

## Воспроизводимый offline-gate

Файл `mobile/ios/Tools/xray_apple_pinned_asset.json` хранит только public pin. Скрипт `mobile/ios/Tools/verify_xray_apple_provenance.py` принимает локальный ZIP и `go.mod`, проверяет строгие sha256, ожидаемый Xray-core commit/version, структуру библиотеки, не допускает path traversal, symlink и duplicate/archive bomb. **Не распаковывает и не исполняет полученный архив.**

```shell
python3 mobile/ios/Tools/verify_xray_apple_provenance.py \
  --asset /path/to/libxray-apple-cgo.zip \
  --go-mod /path/to/pinned-go.mod
```

Результат на фактическом upstream архиве: `provenance_hashes_and_structure_match_only`, 60 Go entries, 28 archive members. Новые hermetic pytest-кейсы проверяют подмену ZIP, подмену Go dependencies, path traversal, symbolic link и отсутствие включения Xray в production `project.yml`.

## Открытые ограничения

- [ ] Независимо установить лицензии **всех** 60 Go module dependencies и связанный транзитивный граф, сохранить license notices/source correspondence для MPL.
- [ ] Собрать из официальных исходников на закреплённой Go 1.27.3 toolchain (сейчас отсутствует) с pin reproducible build; сопоставить полученные iOS бинарники.
- [ ] Отдельно верифицировать Apple code-signing, memory/headroom App Extension, iOS export compliance, entitlements/privacy.
- [ ] Не размещать R&D архив в production IPA, пока физическое egress и release gates не пройдены.

## 15 ноября — исходная сборка iPhoneOS и инвентаризация

Официальный Go1.27.3 darwin-arm64 archive (68196737 bytes, sha256 `dd3908cf20959d798c1e06ebe5b72213f0505ce01373b40ce3110975a6cd99c2`) извлечён в отдельный R&D каталог, системный Go не менялся. Annotated tag object и peeled commit сверены с upstream; go.mod/go.sum проверены по `Tools/xray_source_pins.json`. Модули загружены с Go proxy и проверены `go mod verify`; offline `go list` для `./cgo_bridge`, iOS arm64, CGO, ios tag, mod readonly дал 688 пакетов, 48 модулей (включая libXray). С Go runtime: 49 компонентов и 66 оригинальных корневых файлов LICENSE/NOTICE/PATENTS/etc, все SHA-256 сверены. `Tools/inventory_xray_source_licenses.py`. Комплект в native-artifacts/xray-source-20261115/ios-license-inventory. Это не полный бинарный SBOM и не освобождение от проверки вложенных notices/MPL.

`Tools/build_xray_pinned_source_ios.sh` повторяет закреплённую offline сборку c-archive без глобального GOENV/подписания/деплоя. Две сборки и линковка arm64 iOS15.0 SDK27.1 прошли; для пробной линковки нужны SystemConfiguration, CoreFoundation, Security, resolv. 15/15 содержимых AR members и заголовки локально совпадают, полные архивы отличаются. SHA-256 первой local `811a60e6a3a8e6111fa1dba60045a2b3b0553b3d81c939e36414c7b2dd020df8`, repeat `ae21cd9ec02d3e03ff6e0c18f78c14d62c484054ef18b05f559879aef6b93cc3`, upstream iOS `3836115b390f21b31468c866f1a28c0100bd080cc74d3bdfa7fb76027a0d36a3`. Upstream binary independent reproducibility remains open; no phone runtime acceptance or publication.

## 15 ноября — локальная проверка самостоятельно собранного Xray

`Tools/validate_xray_source_lifecycle.sh` строит macOS/arm64 c-archive из того же чистого pinned commit и verified cache, сравнивает с проверенным Apple ZIP. Для каждой библиотеки: VLESS без/с Vision 2/2, проверка корректной и отклонение синтаксически повреждённой WG конфигурации, три цикла runXray/getXrayState/stopXray/getXrayState. Синтетические ключи, UDP peer и SOCKS listener на loopback, никаких forwarding requests, внешних соединений или изменений VPN. Повторный запуск runner PASS. Это доказательство ограниченной паритетности API и жизненного цикла на macOS, не data-plane и не приёмка iPhoneOS. Pytest11/11. Сравнение iPhoneOS AR: local/upstream 15 members каждый, точных совпадений payload 2/15, отличаются go.o и 12 C object members; локальные повторы 15/15. Следовательно upstream-бинарник нельзя считать независимо побайтово воспроизведённым.

## 15 ноября — source candidate в NativeLab и вложенные notices

`APL_QA_XRAY_SOURCE_CANDIDATE` uses only the exact reviewed iPhoneOS source archive/header SHA-256 pins in `xray_source_pins.json`. The existing upstream ZIP is verified for the baseline module map; candidate copied and reverified. Source mode rejects approved-sign-lab, never installs; default upstream path retained. Full isolated unsigned host/NE build + symbols CGoInvoke and tun2proxy_run_with_cli_args passed. Export `native-artifacts/native-source-xray-unsigned-20261115`, XRAY-ORIGIN, XRAY-INPUT-SHA256SUMS and NATIVE-SHA256SUMS; host/NE hashes checked; no embedded profile/dylib. This is compile/link evidence only, not packet-plane acceptance or production permission. Inventory runner now covers package ancestor directories for actual iOS source graph: four additional notices (compress/internal/snapref, compress/zstd/internal/xxhash, utls/dicttls, xray-core/transport/internet/masque/connectip). 49 components, 70 SHA-verified files under `native-artifacts/xray-source-20261115/ios-license-inventory-nested`. Not final binary SBOM or complete clearance. Targeted pytest20/20. No owner device changes.
