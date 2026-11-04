import Foundation

/// Context-specific import wording in 50 ProxyImport.strings catalogs.
/// 'Preview' is intentionally different from connectivity 'Check'. The
/// curated legacy priority translations stay available as a safe fallback.
enum ProxyImportUX {
    private static let english: [String: String] = [
        "Тип прокси по умолчанию": "Default proxy protocol",
        "Вставьте ссылки, IP:порт:логин:пароль или TXT/CSV/XML до 200 прокси. Тип выше применяется только к строкам без протокола.": "Paste proxy links, IP:port:user:password, or import up to 200 proxies from TXT/CSV/XML. The selected protocol only applies to entries without one.",
        "Импорт прокси": "Import proxies",
        "Импортировать прокси": "Import proxies",
        "Ссылка или список прокси": "Proxy link or list",
        "Вставьте ссылку или несколько ссылок — по одной в строке. HTTP, HTTPS и SOCKS5.": "Paste one proxy link per line. HTTP, HTTPS and SOCKS5 are supported.",
        "Текст ссылок на прокси": "Proxy link text",
        "Вставить из буфера": "Paste from clipboard",
        "Буфер обмена не содержит ссылки на прокси": "No proxy link found on the clipboard",
        "Выбрать файл": "Choose file",
        "Сканировать QR-код": "Scan QR code",
        "Проверить": "Preview",
        "Предпросмотр": "Preview",
        "Новых профилей к добавлению:": "New profiles to add:",
        "Повторяющиеся и существующие профили будут пропущены": "Duplicate and existing profiles will be skipped",
        "Все найденные профили уже добавлены": "All these profiles are already saved",
        "Импортировать профили": "Import profiles",
        "Все профили уже добавлены": "All profiles have already been added",
        "Не удалось сохранить профили. Изменения отменены": "Could not save profiles. Changes were rolled back.",
        "Не удалось полностью отменить импорт. Проверьте список профилей": "Import could not be completely rolled back. Check the saved profiles.",
        "Закрыть": "Close",
        "Сканирование QR": "QR scanner",
        "Отмена": "Cancel",
        "Камера готова — наведите на QR-код": "Camera ready — point at a QR code",
        "Запуск камеры...": "Starting camera…",
        "Нет доступа к камере": "Camera access is denied",
        "Камера недоступна": "Camera is unavailable",
        "Не удалось открыть камеру": "Could not open the camera",
        "Не удалось запустить сканирование": "Could not start QR scanning",
        "Открыть настройки камеры": "Open camera settings",
        "Не удалось прочитать файл. Выберите текстовый файл UTF-8.": "Could not read the file. Choose a UTF-8 text file.",
        "Поддерживаются ссылки http://, https:// и socks5://": "Supported links: http://, https:// and socks5://",
        "Поддерживаются ссылки HTTP/HTTPS/SOCKS5 и IP:порт:логин:пароль": "Supported: HTTP/HTTPS/SOCKS5 links and IP:port:user:password",
        "Некорректный адрес, порт или формат списка прокси": "Invalid proxy address, port, or list format",
        "Некорректный адрес или порт прокси": "Invalid proxy address or port",
        "Слишком большой файл или список прокси": "Proxy file or list is too large",
        "Не найдены ссылки на прокси": "No proxy links found",
        "Не найдены ссылки или записи прокси": "No proxy links or entries found",
        "Импортировать по ссылке или QR-коду": "Import from link or QR code",
        "Если у вас есть ссылка или QR-код от поставщика, импортируйте профиль без ручного ввода.": "Have a link or QR code from your provider? Import instead of typing the settings manually.",
    ]

    private static let priority: [String: [String: String]] = [
        "es": ["Импорт прокси": "Importar proxies", "Импортировать прокси": "Importar proxies", "Вставить из буфера": "Pegar del portapapeles", "Сканировать QR-код": "Escanear código QR", "Импортировать профили": "Importar perfiles", "Проверить": "Vista previa", "Предпросмотр": "Vista previa", "Импортировать по ссылке или QR-коду": "Importar con enlace o código QR"],
        "fr": ["Импорт прокси": "Importer des proxys", "Импортировать прокси": "Importer des proxys", "Вставить из буфера": "Coller du presse-papiers", "Сканировать QR-код": "Scanner un code QR", "Импортировать профили": "Importer les profils", "Проверить": "Aperçu", "Предпросмотр": "Aperçu", "Импортировать по ссылке или QR-коду": "Importer par lien ou code QR"],
        "de": ["Импорт прокси": "Proxys importieren", "Импортировать прокси": "Proxys importieren", "Вставить из буфера": "Aus Zwischenablage einfügen", "Сканировать QR-код": "QR-Code scannen", "Импортировать профили": "Profile importieren", "Проверить": "Vorschau", "Предпросмотр": "Vorschau", "Импортировать по ссылке или QR-коду": "Per Link oder QR-Code importieren"],
        "he": ["Импорт прокси": "ייבוא שרתי פרוקסי", "Импортировать прокси": "ייבוא שרתי פרוקסי", "Вставить из буфера": "הדבקה מהלוח", "Сканировать QR-код": "סריקת קוד QR", "Импортировать профили": "ייבוא פרופילים", "Проверить": "תצוגה מקדימה", "Предпросмотр": "תצוגה מקדימה", "Импортировать по ссылке или QR-коду": "ייבוא מקישור או מקוד QR"],
        "ar": ["Импорт прокси": "استيراد البروكسي", "Импортировать прокси": "استيراد البروكسي", "Вставить из буфера": "لصق من الحافظة", "Сканировать QR-код": "مسح رمز QR", "Импортировать профили": "استيراد الملفات الشخصية", "Проверить": "معاينة", "Предпросмотр": "معاينة", "Импортировать по ссылке или QR-коду": "استيراد عبر رابط أو رمز QR"],
        "fa": ["Импорт прокси": "درون‌ریزی پروکسی", "Импортировать прокси": "درون‌ریزی پروکسی", "Вставить из буфера": "جای‌گذاری از کلیپ‌بورد", "Сканировать QR-код": "اسکن کد QR", "Импортировать профили": "درون‌ریزی پروفایل‌ها", "Проверить": "پیش‌نمایش", "Предпросмотр": "پیش‌نمایش", "Импортировать по ссылке или QR-коду": "درون‌ریزی با پیوند یا کد QR"],
    ]

    static func text(_ russian: String) -> String {
        let language = AppL10n.effectiveLanguage
        if language == "ru" { return russian }
        if let value = priority[language]?[russian] { return value }
        let contextual = AppL10n.tr(russian, table: "ProxyImport")
        if contextual != russian { return contextual }
        let localized = AppL10n.tr(russian)
        if localized != russian { return localized }
        return english[russian] ?? "Import could not be completed. Check the proxy link."
    }

    static func error(_ error: Error) -> String {
        switch error {
        case ProxyImportError.unsupported: return text("Поддерживаются ссылки HTTP/HTTPS/SOCKS5 и IP:порт:логин:пароль")
        case ProxyImportError.invalid: return text("Некорректный адрес, порт или формат списка прокси")
        case ProxyImportError.tooLarge: return text("Слишком большой файл или список прокси")
        case ProxyImportError.empty: return text("Не найдены ссылки на прокси")
        default: return text("Не удалось прочитать файл. Выберите текстовый файл UTF-8.")
        }
    }
}
