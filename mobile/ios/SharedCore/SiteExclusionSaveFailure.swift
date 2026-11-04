import Foundation

/// Pure fail-closed presentation classifier. UI must never display raw
/// Error.localizedDescription from persisted exclusions or VPN reconnect.
enum SiteExclusionSaveFailure: Equatable {
    case invalidAddress
    case maskUnsupported
    case tooManyManual
    case graphInvalidParent
    case graphInvalidChild
    case graphLimit
    case unknown

    static func classify(_ error: Error) -> Self {
        if let invalid = error as? SiteExclusionError {
            switch invalid {
            case .unsupportedMask: return .maskUnsupported
            case .tooMany: return .tooManyManual
            case .malformedIPv6, .whitespace, .malformed, .tooLong: return .invalidAddress
            }
        }
        if let graph = error as? SmartGraphError {
            switch graph {
            case .invalidParent: return .graphInvalidParent
            case .invalidChild: return .graphInvalidChild
            case .tooMany: return .graphLimit
            }
        }
        return .unknown
    }

    /// These graph keys already exist in 64 SmartExclusions.strings catalogs.
    var translatedGraphKey: String? {
        switch self {
        case .graphInvalidParent: return "Некорректный домен сайта"
        case .graphInvalidChild: return "Связанный домен не принадлежит сайту"
        case .graphLimit: return "Превышен безопасный предел связанных доменов"
        default: return nil
        }
    }

    /// Only bounded, code-defined strings. No arbitrary exception or
    /// filesystem/Keychain details may enter a presentation.
    var russianFallback: String {
        switch self {
        case .invalidAddress: return "Проверьте адрес исключения."
        case .maskUnsupported: return "Укажите конкретный адрес — маски не поддерживаются."
        case .tooManyManual: return "Можно сохранить не более 32 исключений."
        case .graphInvalidParent: return "Некорректный домен сайта."
        case .graphInvalidChild: return "Связанный домен не принадлежит сайту."
        case .graphLimit: return "Превышен безопасный предел связанных доменов."
        case .unknown: return "Не удалось сохранить исключения. Проверьте настройки и повторите."
        }
    }

    var englishFallback: String {
        switch self {
        case .invalidAddress: return "Check the excluded domain or IP address."
        case .maskUnsupported: return "Use a specific address; wildcard masks are not supported."
        case .tooManyManual: return "You can save at most 32 exclusions."
        case .graphInvalidParent: return "Invalid site domain."
        case .graphInvalidChild: return "The related domain does not belong to the site."
        case .graphLimit: return "The safe related-domain limit was exceeded."
        case .unknown: return "Could not save exclusions. Check your settings and retry."
        }
    }
}
