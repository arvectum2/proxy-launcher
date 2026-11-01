import SwiftUI

enum AppDestination: String, CaseIterable, Identifiable {
    case home
    case profiles
    case activity
    case settings

    var id: String { rawValue }
    var title: String {
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
