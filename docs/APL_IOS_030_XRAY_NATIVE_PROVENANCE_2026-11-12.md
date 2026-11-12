# APL iOS 0.3.0 — pinned native Xray provenance / offline supply-chain gate

Дата 12.11.2026. **Это инвентаризация и проверка происхождения, не полный SBOM и не разрешение на распространение чужого бинарника.**

| Проверяемое поле | Фактический результат |
| --- | --- |
| Upstream | `XTLS/libXray` |
| Версия и исходный commit | `v26.11.9`, `71d9d443aa88ff939ab6ce22b82aa4b2adcc4d9f` |
| Apple CGO asset | `libxray-apple-cgo.zip` |
| SHA-256 (сверен с release asset) | `7c58346709f1856782a48d8f9926fb815c8ad1bbaf9e5d9dec4ee0cd1f41ed6f` |
| Закреплённый `go.mod` SHA-256 | `6cae0b0bb7f8fb6718b7e357ce28103161949c803901f7233bd9a8a862f56b02` |
| Xray-core transitive module | `github.com/xtls/xray-core v1.260327.1-0.20261109052709-676eaf66f8f0` |
| Go toolchain по upstream | `go 1.27.3`, на Mac mini пока отсутствует |
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
