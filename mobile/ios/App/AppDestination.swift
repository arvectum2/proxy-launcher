import SwiftUI

enum AppDestination: String, CaseIterable, Identifiable {
    case home
    case profiles
    case activity
    case settings

    var id: String { rawValue }
    /// Native short tab labels for compact iPhones. Longer general translations
    /// remain intact for headers, settings and accessibility content. The system
    /// tab bar only has four narrow slots (especially iPhone SE + larger text).
#if !targetEnvironment(macCatalyst)
    private static let compactTabLabels: [String: [AppDestination: String]] = [
        "be": [.home: "Галоўная", .profiles: "Профілі", .activity: "Падзеі", .settings: "Налады"],
        "et": [.home: "Avaleht", .profiles: "Profiilid", .activity: "Tegevus", .settings: "Seaded"],
        "lv": [.home: "Sākums", .profiles: "Profili", .activity: "Darbība", .settings: "Iestat."],
        "lt": [.home: "Pradžia", .profiles: "Profiliai", .activity: "Veikla", .settings: "Nuostatos"],
        "ka": [.home: "მთავარი", .profiles: "პროფილები", .activity: "აქტივობა", .settings: "პარამ."],
        "hy": [.home: "Գլխավոր", .profiles: "Պրոֆիլներ", .activity: "Ակտիվ.", .settings: "Կարգավ."],
        "az": [.home: "Ana səh.", .profiles: "Profillər", .activity: "Fəallıq", .settings: "Ayarlar"],
        "kk": [.home: "Басты", .profiles: "Профильдер", .activity: "Белсенділік", .settings: "Баптау"],
        "tk": [.home: "Baş sah.", .profiles: "Profiller", .activity: "Işjeňlik", .settings: "Sazlama"],
        "ky": [.home: "Башкы", .profiles: "Профилдер", .activity: "Аракеттер", .settings: "Жөндөө"],
        "tg": [.home: "Асосӣ", .profiles: "Профилҳо", .activity: "Фаъолият", .settings: "Танзимот"],
        // Additional longer older translations would overlap adjacent slots.
        "ar": [.profiles: "ملفاتي"],
        "ca": [.settings: "Opcions"],
        "da": [.settings: "Opsætning"],
        "de": [.settings: "Optionen"],
        "el": [.activity: "Συμβάντα"],
        "ha": [.profiles: "Furofayil"],
        "it": [.settings: "Opzioni"],
        "kn": [.profiles: "ಪ್ರೊಫೈಲ್", .settings: "ಸೆಟ್ಟಿಂಗ್"],
        "ml": [.settings: "സെറ്റിങ്"],
        "nb": [.settings: "Oppsett"],
        "nl": [.settings: "Opties"],
        "pl": [.home: "Start"],
        "pt-BR": [.settings: "Ajustes"],
        "sv": [.settings: "Inställ."],
        "ta": [.profiles: "சுயவிவரம்"],
        "te": [.settings: "సెట్టింగ్స్"],
        "uk": [.settings: "Параметри"]
    ]
#endif

    var title: String {
#if !targetEnvironment(macCatalyst)
        if let short = Self.compactTabLabels[AppL10n.effectiveLanguage]?[self] {
            return short
        }
#endif
        switch self {
        case .home:
#if targetEnvironment(macCatalyst)
            return AppL10n.tr("Главная")
#else
            return AppL10n.tr("Домой")
#endif
        case .profiles: return AppL10n.tr("Профили")
        case .activity: return AppL10n.tr("Активность")
        case .settings: return AppL10n.tr("Настройки")
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .profiles: return "rectangle.stack"
        case .activity: return "waveform.path.ecg"
        case .settings: return "gearshape"
        }
    }
}
