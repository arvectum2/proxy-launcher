import Foundation

enum SiteExclusionError: LocalizedError, Equatable {
    case malformedIPv6, unsupportedMask, whitespace, malformed, tooLong, tooMany

    var errorDescription: String? {
        switch self {
        case .malformedIPv6: return "Некорректный IPv6-адрес"
        case .unsupportedMask: return "Маски пока не поддерживаются; добавьте конкретный хост"
        case .whitespace: return "Адрес не должен содержать пробелы"
        case .malformed: return "Некорректный адрес"
        case .tooLong: return "Слишком длинный адрес"
        case .tooMany: return "Можно сохранить не более 32 исключений"
        }
    }
}

enum SiteExclusionPolicy {
    static let maxEntries = 32
    static let maxResolvedAddresses = 128

    static func normalize(_ raw: String) throws -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        if let hash = value.firstIndex(of: "#") {
            value = String(value[..<hash]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let scheme = value.range(of: "://") { value = String(value[scheme.upperBound...]) }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("[") {
            guard let end = value.firstIndex(of: "]"), end > value.startIndex else {
                throw SiteExclusionError.malformedIPv6
            }
            value = String(value[value.index(after: value.startIndex)..<end])
        } else if value.filter({ $0 == ":" }).count == 1, let colon = value.lastIndex(of: ":") {
            let host = String(value[..<colon])
            let port = String(value[value.index(after: colon)...])
            if !port.isEmpty, port.allSatisfy({ $0.isNumber }) { value = host }
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SiteExclusionError.malformed }
        if value.contains("*") || value.contains("?") || value.hasPrefix(".") { throw SiteExclusionError.unsupportedMask }
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { throw SiteExclusionError.whitespace }
        if value.contains("@") || value.contains("[") || value.contains("]") { throw SiteExclusionError.malformed }
        if value.count > 253 { throw SiteExclusionError.tooLong }
        return value
    }

    static func normalizeAll<S: Sequence>(_ entries: S) throws -> [String] where S.Element == String {
        var unique = Set<String>()
        for raw in entries {
            if let value = try normalize(raw) { unique.insert(value) }
        }
        if unique.count > maxEntries { throw SiteExclusionError.tooMany }
        return unique.sorted()
    }
}
