# APL-REG-001D — руководство по установке и эксплуатации

Версия: `0.2.9`

## 1. Получение и проверка дистрибутива

Канонический публичный релиз: `https://github.com/arvectum2/proxy-launcher/releases/tag/v0.2.9`. Российское зеркало: `https://gitverse.ru/arvectum/proxy-launcher/releases`.

Перед установкой скачать нужный пакет и `SHA256SUMS.txt`, затем сверить SHA-256. GitVerse из-за ограничений расширений публикует `.exe`, `.deb` и `.rpm` в детерминированных однофайловых ZIP-обёртках; после распаковки байты пакета должны совпадать с canonical payload.

## 2. Windows x64

### Установка

Запустить `Arvectum-Proxy-Launcher-0.2.9-windows-x64-setup.exe`. Установка выполняется для текущего пользователя в `%LOCALAPPDATA%\Programs\ArvectumProxyLauncher`.

Также доступен portable-архив `Arvectum-Proxy-Launcher-0.2.9-windows-x64-portable.zip`.

Релиз 0.2.9 не заявляет Authenticode-подпись, поэтому Windows может показать SmartScreen для неизвестного издателя. Для установки не требуется отключать Defender, SmartScreen или Controlled Folder Access.

### Удаление

Для Setup-редакции использовать штатное удаление приложения Windows. Перед удалением штатно отключить активный proxy lifecycle и убедиться, что системная proxy-конфигурация восстановлена. При наличии recovery evidence сначала выполнить восстановление из приложения.

## 3. Astra Linux 1.8 x86-64

### Установка

```bash
sudo apt install ./Arvectum-Proxy-Launcher-0.2.9-astra-linux-amd64.deb
```

### Запуск

```bash
arvectum-proxy-launcher
```

Целевая среда использует NetworkManager и GSettings (`libglib2.0-bin`). На Astra/Fly PAC публикуется через NetworkManager и desktop GSettings, сохраняя rollback/recovery semantics.

### Удаление

Сначала штатно отключить Proxy Launcher и проверить восстановление исходного network/proxy state. Затем удалить установленный пакет стандартными средствами APT/DPKG в соответствии с именем пакета, отображаемым системой (`dpkg -l`). Не удалять вручную recovery evidence до завершения штатного rollback.

## 4. RED ОС 8.0.3 x86-64

### Установка

```bash
sudo dnf install ./Arvectum-Proxy-Launcher-0.2.9-redos-linux-x86_64.rpm
```

Если локальная политика использует другой штатный RPM frontend, допускается установка через него без изменения пакета.

### Запуск

```bash
arvectum-proxy-launcher
```

Интерфейс платформы должен показывать `Linux / RED OS`.

### Удаление

Сначала отключить активный Proxy Launcher и убедиться в завершении rollback/recovery. Имя установленного RPM проверить через системный package database; удалить пакет штатным DNF/RPM frontend. Не удалять вручную durable recovery evidence, пока rollback не закрыт.

## 5. Базовый рабочий сценарий

1. Запустить приложение.
2. Ввести/выбрать параметры внешнего upstream proxy, предоставленного пользователем или заказчиком.
3. Проверить `no_proxy`/bypass исключения.
4. Включить Proxy Launcher.
5. Убедиться, что локальные endpoint'ы доступны, а системный PAC/proxy указывает на управляемую конфигурацию.
6. Проверить целевое приложение/браузер.
7. Для завершения использовать штатное отключение Proxy Launcher.
8. Проверить, что исходные network/proxy параметры восстановлены.

## 6. Аварийное восстановление

При сбое/перезапуске приложение использует durable rollback evidence. Recovery должен восстанавливать только доказуемые Arvectum/original значения. Если пользователь или администратор изменил управляемое поле на третье значение, программа должна остановить destructive restore (`fail-closed`) и сохранить evidence для безопасного повторного решения.

Для экспертизы этот сценарий воспроизводится по `APL_REG_001D_EXPERT_TEST_PROCEDURE_RU.md`.

## 7. Ограничения и меры безопасности

- Не вводить в публичные журналы пароли upstream proxy.
- Не отключать защитные механизмы ОС ради установки.
- Не считать Proxy Launcher VPN или СЗИ.
- Не удалять вручную recovery evidence при активной незавершённой сессии.
- Сверять hash экземпляра с `SHA256SUMS.txt` перед воспроизводимой экспертизой.
