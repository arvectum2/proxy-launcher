import Foundation

/// Source-only first iteration: curated main-market translations and a safe
/// English fallback for other UI languages. Native editorial review of all
/// 64 locales is a release gate, not a reason to expose raw Russian UI.
enum ProfileShareUX {
    private static let english = [
        "Поделиться": "Share",
        "Поделиться профилем": "Share proxy profile",
        "Отправить QR-код": "Send QR code",
        "Не удалось создать QR-код": "Could not create QR code",
        "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.":
            "This QR code contains the proxy address and may include a username and password. Share it only with someone you trust."
    ]

    private static let translations: [String: [String: String]] = [
        "de": ["Поделиться": "Teilen",
               "Поделиться профилем": "Proxyprofil teilen",
               "Отправить QR-код": "QR-Code senden",
               "Не удалось создать QR-код": "QR-Code konnte nicht erstellt werden",
               "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "Dieser QR-Code enthält die Proxyadresse und möglicherweise Benutzername und Passwort. Nur an vertrauenswürdige Personen weitergeben."],
        "fr": ["Поделиться": "Partager",
               "Поделиться профилем": "Partager le profil proxy",
               "Отправить QR-код": "Envoyer le code QR",
               "Не удалось создать QR-код": "Impossible de créer le code QR",
               "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "Ce code QR contient l’adresse du proxy et peut inclure un identifiant et un mot de passe. Ne le partagez qu’avec des personnes de confiance."],
        "es": ["Поделиться": "Compartir",
               "Поделиться профилем": "Compartir perfil de proxy",
               "Отправить QR-код": "Enviar código QR",
               "Не удалось создать QR-код": "No se pudo crear el código QR",
               "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "Este código QR contiene la dirección del proxy y puede incluir usuario y contraseña. Compártelo solo con personas de confianza."],
        "it": ["Поделиться": "Condividi",
               "Поделиться профилем": "Condividi profilo proxy",
               "Отправить QR-код": "Invia codice QR",
               "Не удалось создать QR-код": "Impossibile creare il codice QR",
               "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "Il codice QR contiene l'indirizzo proxy e può includere nome utente e password. Condividilo solo con persone fidate."],
        "pt-BR": ["Поделиться": "Compartilhar",
                  "Поделиться профилем": "Compartilhar perfil de proxy",
                  "Отправить QR-код": "Enviar código QR",
                  "Не удалось создать QR-код": "Não foi possível criar o código QR",
                  "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "Este QR code contém o endereço do proxy e pode incluir usuário e senha. Compartilhe apenas com pessoas de confiança."],
        "pt-PT": ["Поделиться": "Partilhar",
                  "Поделиться профилем": "Partilhar perfil de proxy",
                  "Отправить QR-код": "Enviar código QR",
                  "Не удалось создать QR-код": "Não foi possível criar o código QR",
                  "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "Este código QR contém o endereço do proxy e pode incluir utilizador e palavra-passe. Partilhe-o apenas com pessoas de confiança."],
        "ja": ["Поделиться": "共有",
               "Поделиться профилем": "プロキシプロファイルを共有",
               "Отправить QR-код": "QRコードを送信",
               "Не удалось создать QR-код": "QRコードを作成できませんでした",
               "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "このQRコードにはプロキシのアドレスが含まれ、ユーザー名とパスワードが含まれる場合があります。信頼できる相手にのみ共有してください。"],
        "ko": ["Поделиться": "공유",
               "Поделиться профилем": "프록시 프로필 공유",
               "Отправить QR-код": "QR 코드 보내기",
               "Не удалось создать QR-код": "QR 코드를 생성할 수 없습니다",
               "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "이 QR 코드에는 프록시 주소가 포함되며 사용자 이름과 비밀번호가 포함될 수 있습니다. 신뢰하는 사람에게만 공유하세요."],
        "zh-Hans": ["Поделиться": "分享",
                    "Поделиться профилем": "分享代理配置",
                    "Отправить QR-код": "发送二维码",
                    "Не удалось создать QR-код": "无法生成二维码",
                    "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "此二维码包含代理地址，也可能包含用户名和密码。请仅与可信任的人分享。"],
        "zh-Hant": ["Поделиться": "分享",
                    "Поделиться профилем": "分享代理設定",
                    "Отправить QR-код": "傳送 QR 碼",
                    "Не удалось создать QR-код": "無法產生 QR 碼",
                    "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "此 QR 碼包含代理伺服器位址，也可能包含使用者名稱和密碼。請僅與信任的人分享。"],
        "uk": ["Поделиться": "Поділитися",
               "Поделиться профилем": "Поділитися профілем проксі",
               "Отправить QR-код": "Надіслати QR-код",
               "Не удалось создать QR-код": "Не вдалося створити QR-код",
               "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "Цей QR-код містить адресу проксі та може містити логін і пароль. Діліться ним лише з людьми, яким довіряєте."],
        "pl": ["Поделиться": "Udostępnij",
               "Поделиться профилем": "Udostępnij profil proxy",
               "Отправить QR-код": "Wyślij kod QR",
               "Не удалось создать QR-код": "Nie udało się utworzyć kodu QR",
               "QR-код содержит адрес прокси и может содержать логин и пароль. Передавайте его только тем, кому доверяете.": "Kod QR zawiera adres serwera proxy i może zawierać login oraz hasło. Udostępniaj go tylko zaufanym osobom."]
    ]

    static func text(_ key: String) -> String {
        let language = AppL10n.effectiveLanguage
        if language == "ru" { return key }
        return translations[language]?[key] ?? english[key] ?? "Share"
    }
}
