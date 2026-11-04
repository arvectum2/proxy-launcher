import Foundation
import Darwin

/// Fixed recovery instructions for known Apple VPN configuration failures.
/// Only code-defined values can enter UI; no NSError description is interpolated.
enum ProxyRecoveryHint: Equatable {
    case vpnDisabled
    case vpnStale
    case vpnInvalid

    var localizationKey: String {
        switch self {
        case .vpnDisabled:
            return "iOS отключила конфигурацию VPN и не позволила включить её автоматически. Откройте Настройки → VPN и разрешите Arvectum Proxy Launcher, затем повторите подключение."
        case .vpnStale:
            return "Конфигурация VPN была изменена системой. Перезапустите подключение — приложение перечитает и восстановит её."
        case .vpnInvalid:
            return "iOS отклонила конфигурацию Packet Tunnel. Конфигурация была восстановлена, но системе всё ещё не удалось её запустить."
        }
    }
}

/// Stable, non-sensitive diagnostic codes: never include a server address,
/// account name, password, system error description or arbitrary response body.
enum ProxyFailureReason: String, Codable, Equatable, CaseIterable {
    case offline
    case dns
    case tcp
    case tls
    case authentication
    case http407
    case rejected
    case timeout
    case tunnel
    case protocolMismatch
    case unknown

    var code: String {
        switch self {
        case .offline: return "NET"
        case .dns: return "DNS"
        case .tcp: return "TCP"
        case .tls: return "TLS"
        case .authentication: return "AUTH"
        case .http407: return "HTTP 407"
        case .rejected: return "PROXY"
        case .timeout: return "TIMEOUT"
        case .tunnel: return "VPN"
        case .protocolMismatch: return "PROTOCOL"
        case .unknown: return "UNKNOWN"
        }
    }

    /// Use only keys already translated in all 64 supported iOS languages.
    /// Neither the raw NSError description nor proxy credentials reach UI.
    var recoveryGuidanceKey: String {
        switch self {
        case .dns, .tcp, .timeout:
            return "Проверьте адрес и порт прокси"
        case .authentication, .http407:
            return "Логин и пароль нужны только для прокси с авторизацией."
        case .tls, .protocolMismatch:
            return "Если тип подключения неизвестен, уточните его у поставщика. После заполнения нажмите «Сохранить»."
        case .offline, .rejected, .tunnel, .unknown:
            return "Следите за статусом соединения. Если подключение не удалось, проверьте адрес, порт, тип и учётные данные."
        }
    }

    /// Construct a safe and localized diagnostic from a finite set of literals.
    /// Caller injects its localization function; no error fields are rendered.
    static func safeDisplay(for error: Error, translate: (String) -> String) -> String {
        let reason = classify(error)
        let hint = (error as? ProxyDiagnosticError)?.recoveryHint?.localizationKey
            ?? reason.recoveryGuidanceKey
        return "\(translate("Недоступен")) · \(reason.code)\n\(translate(hint))"
    }

    /// An HTTP 407 is always an authentication failure, including Digest
    /// challenges. No unverified CONNECT response can be treated as success.
    static func forHTTPConnectStatus(_ status: Int) -> Self? {
        if (200...299).contains(status) { return nil }
        if status == 407 { return .http407 }
        return .rejected
    }

    /// The most actionable failure wins when an AUTO profile tries multiple
    /// transports. Do not claim a diagnosis if the error was not classified.
    static func mostRelevant(_ reasons: [Self]) -> Self {
        let priority: [Self] = [.http407, .authentication, .offline, .dns, .tls, .tcp,
                                .timeout, .rejected, .tunnel, .protocolMismatch, .unknown]
        return priority.first(where: { reasons.contains($0) }) ?? .unknown
    }

    static func classify(_ error: Error) -> Self {
        if let diagnostic = error as? ProxyDiagnosticError { return diagnostic.reason }
        // A timed-out engine handoff is a tunnel failure, not an unknown
        // network problem or a reason to reveal internal socket details.
        if error is TunnelEngineDrainError { return .tunnel }
        return classify(error as NSError, depth: 0)
    }

    private static func classify(_ error: NSError, depth: Int) -> Self {
        switch error.domain {
        case NSURLErrorDomain:
            switch error.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return .offline
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return .dns
            case NSURLErrorCannotConnectToHost:
                return .tcp
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate:
                return .tls
            case NSURLErrorTimedOut:
                return .timeout
            default: break
            }
        case NSPOSIXErrorDomain:
            switch error.code {
            case Int(ENETDOWN), Int(ENETUNREACH), Int(EHOSTUNREACH):
                return .offline
            case Int(ECONNREFUSED), Int(ECONNRESET), Int(ECONNABORTED):
                return .tcp
            case Int(ETIMEDOUT):
                return .timeout
            default: break
            }
        case "ArvectumVPN", "NEVPNErrorDomain":
            return .tunnel
        default: break
        }
        // Only use typed NSError nesting; never try to infer private error
        // details from arbitrary localizedDescription text.
        if depth < 3, let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return classify(underlying, depth: depth + 1)
        }
        return .unknown
    }
}

struct ProxyDiagnosticError: LocalizedError {
    let reason: ProxyFailureReason
    let recoveryHint: ProxyRecoveryHint?

    init(_ reason: ProxyFailureReason, recoveryHint: ProxyRecoveryHint? = nil) {
        self.reason = reason
        self.recoveryHint = recoveryHint
    }

    var errorDescription: String? { "Прокси недоступен (\(reason.code))" }
}
