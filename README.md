# Arvectum Proxy Launcher

Arvectum Proxy Launcher — кроссплатформенный локальный клиент для безопасного управления системным proxy/PAC, `no_proxy`, локальными HTTP/SOCKS5 endpoint'ами и восстановления сетевых настроек.

Arvectum Proxy Launcher is a cross-platform local client for safe system proxy/PAC management, `no_proxy`, local HTTP/SOCKS5 endpoints, and network-settings recovery.

## Текущий релиз / Current release

**0.2.9** — стабильный релиз для **Windows x64**, **Astra Linux 1.8 x86-64** и **RED OS 8.0.3 x86-64**.

- Canonical GitHub release: https://github.com/arvectum2/proxy-launcher/releases/tag/v0.2.9
- Independent GitVerse mirror: https://gitverse.ru/arvectum/proxy-launcher/releases
- Tag: `v0.2.9`
- Full bilingual release notes: [docs/releases/0.2.9.md](docs/releases/0.2.9.md)
- GitVerse mirror details: [docs/releases/0.2.9-gitverse-mirror.md](docs/releases/0.2.9-gitverse-mirror.md)

### Release assets

GitHub publishes the canonical package bytes under their original names:

- `Arvectum-Proxy-Launcher-0.2.9-windows-x64-setup.exe`
- `Arvectum-Proxy-Launcher-0.2.9-windows-x64-portable.zip`
- `Arvectum-Proxy-Launcher-0.2.9-astra-linux-amd64.deb`
- `Arvectum-Proxy-Launcher-0.2.9-redos-linux-x86_64.rpm`
- Windows: rollback now validates current WinINET and per-user proxy environment state before any mutation; saved/Arvectum mixed states recover, while newer foreign PAC/manual/env changes are preserved fail-closed.
- RED ОС: исправлено восстановление сети после частичного ручного изменения desktop proxy во время активного Proxy Launcher; mixed-state из исходных и Arvectum-значений теперь безопасно восстанавливается, а действительно чужое значение по-прежнему блокирует rollback.
- RED ОС: служебные recovery/capability сообщения используют фактическую платформу `Linux / RED OS`, без остаточных пользовательских ссылок на Astra Linux.
- `SHA256SUMS.txt`

Verify all four packages against `SHA256SUMS.txt` before installation when provenance matters.

---

# Русский

## Windows

Для обычной установки скачайте `Arvectum-Proxy-Launcher-0.2.9-windows-x64-setup.exe` и запустите Setup. Windows может показать SmartScreen для неизвестного издателя: релиз 0.2.9 не заявляет Microsoft Authenticode-подпись. Отключать Defender, SmartScreen или Controlled Folder Access не требуется.

Приложение устанавливается для текущего пользователя в `%LOCALAPPDATA%\Programs\ArvectumProxyLauncher`. Portable-вариант доступен как `Arvectum-Proxy-Launcher-0.2.9-windows-x64-portable.zip`.

## Astra Linux

Пакет `Arvectum-Proxy-Launcher-0.2.9-astra-linux-amd64.deb` предназначен для Astra Linux 1.8 x86-64 и Debian-совместимых систем с NetworkManager и GSettings (`libglib2.0-bin`). Установка:

```bash
sudo apt install ./Arvectum-Proxy-Launcher-0.2.9-astra-linux-amd64.deb
```

Запуск после установки:

```bash
arvectum-proxy-launcher
```

В 0.2.9 сохраняется исправленный в 0.2.6 путь **Firefox → «Использовать системные настройки прокси»** на Astra/Fly: Proxy Launcher публикует PAC не только через NetworkManager, но и в desktop GSettings, сохраняя rollback/recovery и защиту от чужих изменений.

## RED ОС

Пакет `Arvectum-Proxy-Launcher-0.2.9-redos-linux-x86_64.rpm` предназначен для RED OS 8.0.3 x86-64 / KDE Plasma. Установите его через системный пакетный менеджер с правами администратора.

В интерфейсе RED ОС имеет отдельную подпись `Linux / RED OS`; Astra Linux остаётся `Linux / Astra Linux`.

## GitVerse

GitVerse является независимым российским зеркалом публичного релиза. Из-за ограничений форматов release assets `.exe`, `.deb` и `.rpm` транспортируются там как детерминированные однофайловые `.zip`-обёртки. Внутри лежат исходные канонические файлы без изменения байтов; workflow зеркала повторно проверяет SHA-256 каждого payload после публичного скачивания.

Для Astra Linux скачайте `Arvectum-Proxy-Launcher-0.2.9-astra-linux-amd64.deb.zip`. Для RED ОС — `Arvectum-Proxy-Launcher-0.2.9-redos-linux-x86_64.rpm.zip`. Распакуйте соответствующую однофайловую обёртку один раз и установите находящийся внутри пакет.

## Целостность и подпись

`SHA256SUMS.txt` в релизе 0.2.9 покрывает Windows portable, Windows Setup, Astra Linux DEB и RED OS RPM. Российская detached CryptoPro/Rutoken-подпись, опубликованная для исторического релиза 0.2.5, не переносится автоматически на 0.2.9; этот релиз не заявляет такую подпись до отдельного owner-operated signing gate.

---

# English

## Windows

For a normal installation, download `Arvectum-Proxy-Launcher-0.2.9-windows-x64-setup.exe` and run Setup. Windows may show SmartScreen for an unrecognized publisher; release 0.2.9 does not claim Microsoft Authenticode signing. Defender, SmartScreen, and Controlled Folder Access do not need to be disabled.

The application installs per-user under `%LOCALAPPDATA%\Programs\ArvectumProxyLauncher`. A portable package is available as `Arvectum-Proxy-Launcher-0.2.9-windows-x64-portable.zip`.

## Astra Linux

`Arvectum-Proxy-Launcher-0.2.9-astra-linux-amd64.deb` targets Astra Linux 1.8 x86-64 and compatible Debian-family systems with NetworkManager and GSettings (`libglib2.0-bin`). Install it with:

```bash
sudo apt install ./Arvectum-Proxy-Launcher-0.2.9-astra-linux-amd64.deb
```

Then launch:

```bash
arvectum-proxy-launcher
```

Version 0.2.9 retains the **Firefox → Use system proxy settings** fix introduced in 0.2.6 on Astra/Fly: Proxy Launcher publishes the PAC through both NetworkManager and desktop GSettings while preserving rollback/recovery and foreign-change protection.

## RED OS

`Arvectum-Proxy-Launcher-0.2.9-redos-linux-x86_64.rpm` targets RED OS 8.0.3 x86-64 / KDE Plasma. Install it through the system package manager with administrator rights.

RED OS has a distinct `Linux / RED OS` product signature; Astra Linux remains `Linux / Astra Linux`.

## GitVerse

GitVerse is maintained as an independent Russian release mirror. Because GitVerse restricts release-asset extensions, `.exe`, `.deb`, and `.rpm` payloads are transported in deterministic single-file `.zip` wrappers. The original canonical bytes remain unchanged and the mirror workflow re-verifies every canonical payload SHA-256 after public download.

For Astra Linux, download `Arvectum-Proxy-Launcher-0.2.9-astra-linux-amd64.deb.zip`. For RED OS, download `Arvectum-Proxy-Launcher-0.2.9-redos-linux-x86_64.rpm.zip`. Extract the matching single-file wrapper once and install the enclosed package.

## Integrity and signing

Release 0.2.9 `SHA256SUMS.txt` covers the Windows portable ZIP, Windows Setup, Astra Linux DEB, and RED OS RPM. The detached CryptoPro/Rutoken signature published for historical release 0.2.5 is not implicitly carried forward; 0.2.9 does not claim that signature until a separate owner-operated signing gate is completed.

## Build and test

Canonical Windows builds use the pinned clean-build pipeline in `tools/clean_build_windows.ps1`. Canonical Astra/Linux DEB publication reuses the exact successful Ubuntu 22.04 artifact from the release commit's `main` CI run; the same source is also tested on Ubuntu 24.04. Canonical RED OS RPM publication reuses the exact successful Ubuntu 22.04 RPM artifact from the same `main` commit.

Source tests:

```text
python -m unittest discover -s tests -v
```

See [RELEASE_POLICY.md](RELEASE_POLICY.md), [LICENSE](LICENSE), [SECURITY](SECURITY), [CONTRIBUTING](CONTRIBUTING), and [CODE_OF_CONDUCT](CODE_OF_CONDUCT).
