# Arvectum Proxy Launcher

Arvectum Proxy Launcher — локальный Windows-клиент для маршрутизации трафика через настроенный upstream HTTP proxy с локальными HTTP, SOCKS5 и PAC endpoint'ами. Правила `no_proxy.txt` отправляют указанный трафик напрямую.

Arvectum Proxy Launcher is a local Windows client for routing traffic through a configured upstream HTTP proxy while exposing local HTTP, SOCKS5 and PAC endpoints. Entries in `no_proxy.txt` are routed directly.

## Текущий релиз / Current release

**Windows 0.2.5** — текущий публичный стабильный релиз.

- Canonical GitHub release: https://github.com/arvectum2/proxy-launcher/releases/tag/v0.2.5
- Independent GitVerse mirror: https://gitverse.ru/arvectum/proxy-launcher/releases
- GitVerse mirror format and verification: [docs/releases/0.2.5-gitverse-mirror.md](docs/releases/0.2.5-gitverse-mirror.md)
- Tag: `v0.2.5`
- Accepted product source: `9e8ca7e851563082cd7d03d7543ccb360a37ec27`
- Release governance commit: `6509d5e7228a90bb5c0b779ea6e2b9df0e9d0d85`
- Full bilingual release notes: [docs/releases/0.2.5.md](docs/releases/0.2.5.md)

---

# Русский

## Быстрая установка на Windows

1. Откройте официальный релиз [`v0.2.5`](https://github.com/arvectum2/proxy-launcher/releases/tag/v0.2.5).
2. Скачайте `Arvectum-Proxy-Launcher-0.2.5-windows-x64-setup.exe`.
3. Запустите скачанный файл.
4. Windows может показать окно **Microsoft Defender SmartScreen — «Система Windows защитила компьютер»**, потому что версия 0.2.5 пока не имеет Microsoft Authenticode-подписи.
5. В этом окне нажмите **«Подробнее»**, затем **«Выполнить в любом случае»**.
6. Если появится стандартный запрос UAC, подтвердите запуск установщика.
7. После установки запускайте **Arvectum Proxy Launcher** из меню «Пуск».

**Не отключайте Microsoft Defender, SmartScreen или Controlled Folder Access.** Для установки это не требуется.

Приложение устанавливается для текущего пользователя в:

```text
%LOCALAPPDATA%\Programs\ArvectumProxyLauncher
```

Рабочие настройки и изменяемые данные хранятся отдельно в LocalAppData.

### Независимое зеркало GitVerse

Релиз также зеркалируется в GitVerse: https://gitverse.ru/arvectum/proxy-launcher/releases

GitHub остаётся канонической страницей с 9 файлами под исходными именами. GitVerse принимает напрямую не все расширения release assets, поэтому `.exe`, `.json`, `.sig`, `.cer`, `.cmd` и `.ps1` на зеркале помещены в однофайловые `.zip`-обёртки. Внутри находятся исходные файлы без изменений; workflow зеркала скачивает их обратно и проверяет канонический SHA-256 каждого из 9 payload.

Для установки из GitVerse скачайте `Arvectum-Proxy-Launcher-0.2.5-windows-x64-setup.exe.zip`, распакуйте один раз и используйте находящийся внутри исходный Setup. Подробнее: [формат и проверка GitVerse mirror](docs/releases/0.2.5-gitverse-mirror.md).

## Проверка скачанного Setup

SHA-256 официального Setup 0.2.5:

```text
9b5368d67874b7164ee56a245c75db4b23af593a1d72f7e947774516abcc95e3
```

Проверка в PowerShell:

```powershell
Get-FileHash "$env:USERPROFILE\Downloads\Arvectum-Proxy-Launcher-0.2.5-windows-x64-setup.exe" -Algorithm SHA256
```

Если хэш не совпадает, файл не запускайте и скачайте его заново с официальной страницы релиза.

## Portable-версия

Если установка не нужна, можно скачать:

```text
Arvectum-Proxy-Launcher-0.2.5-windows-x64-portable.zip
```

SHA-256 portable ZIP:

```text
5543419da395370599f2609ad6056da393470280d99b21ef342223d01906402e
```

## Подпись российского релиза

Релиз 0.2.5 имеет отдельную российскую цепочку подтверждения целостности: SHA-256 manifest + detached CryptoPro/Rutoken signature сертификатом ООО «Арвектум». В assets релиза опубликованы `SHA256SUMS.txt`, `SHA256SUMS.txt.sig`, `signer-certificate.cer`, `signing-evidence.json` и скрипты проверки.

Эта подпись подтверждает происхождение и целостность опубликованного набора, но **не является Microsoft Authenticode-подписью EXE** и поэтому сама по себе не убирает предупреждение SmartScreen.

---

# English

## Quick Windows installation

1. Open the official [`v0.2.5` release](https://github.com/arvectum2/proxy-launcher/releases/tag/v0.2.5).
2. Download `Arvectum-Proxy-Launcher-0.2.5-windows-x64-setup.exe`.
3. Run the downloaded file.
4. Windows may show **Microsoft Defender SmartScreen — “Windows protected your PC”** because version 0.2.5 does not yet carry a Microsoft Authenticode signature.
5. Click **More info**, then **Run anyway**.
6. Confirm the normal UAC prompt if shown.
7. After installation, launch **Arvectum Proxy Launcher** from the Start menu.

**Do not disable Microsoft Defender, SmartScreen or Controlled Folder Access.** Installation does not require disabling Windows security features.

The application is installed for the current user under:

```text
%LOCALAPPDATA%\Programs\ArvectumProxyLauncher
```

Mutable application state and user settings are stored separately under LocalAppData.

### Independent GitVerse mirror

The release is also mirrored on GitVerse: https://gitverse.ru/arvectum/proxy-launcher/releases

GitHub remains the canonical page exposing all 9 files under their original names. GitVerse does not accept every release-asset extension directly, so `.exe`, `.json`, `.sig`, `.cer`, `.cmd`, and `.ps1` files are carried as single-file `.zip` wrappers on the mirror. Each wrapper contains the unchanged canonical file, and the mirror workflow downloads all assets back and verifies all 9 canonical payload SHA-256 values.

For installation from GitVerse, download `Arvectum-Proxy-Launcher-0.2.5-windows-x64-setup.exe.zip`, extract it once, and use the original Setup contained inside. See [GitVerse mirror format and verification](docs/releases/0.2.5-gitverse-mirror.md).

## Verify the downloaded Setup

Official 0.2.5 Setup SHA-256:

```text
9b5368d67874b7164ee56a245c75db4b23af593a1d72f7e947774516abcc95e3
```

PowerShell verification:

```powershell
Get-FileHash "$env:USERPROFILE\Downloads\Arvectum-Proxy-Launcher-0.2.5-windows-x64-setup.exe" -Algorithm SHA256
```

If the hash does not match, do not run the file. Download it again from the official release page.

## Portable build

If you do not want to install the application, download:

```text
Arvectum-Proxy-Launcher-0.2.5-windows-x64-portable.zip
```

Portable ZIP SHA-256:

```text
5543419da395370599f2609ad6056da393470280d99b21ef342223d01906402e
```

## Russian release signature

Release 0.2.5 also carries a Russian integrity/provenance layer: a SHA-256 manifest and detached CryptoPro/Rutoken signature made with the certificate of ООО «Арвектум». The release assets include `SHA256SUMS.txt`, `SHA256SUMS.txt.sig`, `signer-certificate.cer`, `signing-evidence.json` and verification scripts.

This verifies the integrity and provenance of the published release set, but it is **not a Microsoft Authenticode signature on the EXE**, so it does not by itself suppress SmartScreen warnings.

---

## Release assets

The public `v0.2.5` release contains the installer, portable package and the governed verification/evidence files. Published release assets and the `v0.2.5` tag are immutable under Arvectum release policy and must not be replaced in place.

See [RELEASE_POLICY.md](RELEASE_POLICY.md) for versioning, provenance and release-governance rules.

## Build and test

Canonical Windows build prerequisites: Windows x64 with Python 3.12.10 x64.

PowerShell:

```powershell
pwsh -NoProfile -File .\tools\clean_build_windows.ps1
pwsh -NoProfile -File .\tools\build_windows_installer.ps1
```

Windows PowerShell compatibility path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\clean_build_windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_windows_installer.ps1
```

Source tests:

```powershell
python -m py_compile proxy_core.py proxy_gui.py
python -m unittest discover -s tests -v
```

## License and contribution

See [LICENSE](LICENSE), [SECURITY](SECURITY), [CONTRIBUTING](CONTRIBUTING), and [CODE_OF_CONDUCT](CODE_OF_CONDUCT).
