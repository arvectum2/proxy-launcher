import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Bounded offline parsing of structured vendor exports; no remote entities.
enum ProxyImportStructured {
    private static let aliases: [String: Set<String>] = [
        "host": ["host", "hostname", "ip", "ipaddress", "server", "address", "адрес", "сервер"],
        "port": ["port", "порт"],
        "username": ["username", "user", "login", "логин", "пользователь"],
        "password": ["password", "pass", "passwd", "pwd", "пароль"],
        "type": ["type", "protocol", "scheme", "протокол", "тип"],
        "name": ["name", "label", "title", "название", "имя"]
    ]

    private static func key(_ input: String) -> String {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        return aliases.first { $0.value.contains(normalized) }?.key ?? normalized
    }

    static func looksLikeCSV(_ input: String) -> Bool {
        guard let first = input.components(separatedBy: .newlines).first else { return false }
        for separator: Character in [",", ";", "\t"] where first.contains(separator) {
            let cells = first.split(separator: separator, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            if cells.count >= 2 &&
               ((cells.contains { key($0) == "host" } && cells.contains { key($0) == "port" }) ||
                Int(cells[1]) != nil) { return true }
        }
        return false
    }

    private static func csvDelimiter(_ line: String) -> Character {
        var counts: [Character: Int] = [",": 0, ";": 0, "\t": 0]
        var quoted = false
        for char in line {
            if char == "\"" { quoted.toggle() }
            else if !quoted, counts[char] != nil { counts[char, default: 0] += 1 }
        }
        return [",", ";", "\t"].max { counts[$0, default: 0] < counts[$1, default: 0] } ?? ","
    }

    static func csv(_ input: String, defaultType: ProxyType) throws -> [ImportedProxy] {
        let firstLine = input.components(separatedBy: .newlines).first ?? ""
        let separator = csvDelimiter(firstLine)
        let rows = try csvRows(input, separator: separator)
            .filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        guard let first = rows.first else { throw ProxyImportError.empty }
        let normalized = first.map(key)
        let hasHeader = normalized.contains("host") && normalized.contains("port")
        let columns = hasHeader ? normalized : ["host", "port", "username", "password", "type", "name"]
        let records = hasHeader ? Array(rows.dropFirst()) : rows
        guard !records.isEmpty else { throw ProxyImportError.empty }
        guard records.count <= 200 else { throw ProxyImportError.tooLarge }
        guard columns.contains("host") && columns.contains("port"),
              Set(columns).count == columns.count else { throw ProxyImportError.invalid }
        return try records.map { fields in
            guard fields.count <= columns.count else { throw ProxyImportError.invalid }
            let values = Dictionary(uniqueKeysWithValues: zip(columns, fields))
            let type = try ProxyImport.specifiedType(values["type"], defaultType: defaultType)
            return try ProxyImport.item(host: values["host"] ?? "", port: values["port"] ?? "",
                                        username: values["username"] ?? "", password: values["password"] ?? "",
                                        type: type, name: values["name"] ?? "")
        }
    }

    /// Quoted CSV cells, escaped quotes, embedded line breaks, CRLF support.
    private static func csvRows(_ input: String, separator: Character) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cell = ""
        var quoted = false, closed = false, atStart = true
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { cell.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { cell.append(c) }
            } else if c == "\"" {
                guard atStart else { throw ProxyImportError.invalid }
                quoted = true
            } else if c == separator || c == "\n" || c == "\r" {
                row.append(cell); cell = ""; closed = false; atStart = true
                if c != separator {
                    rows.append(row); row = []
                    if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                }
                if rows.count > 201 { throw ProxyImportError.tooLarge }
            } else {
                guard !closed else { throw ProxyImportError.invalid }
                cell.append(c); atStart = false
            }
            i += 1
        }
        guard !quoted else { throw ProxyImportError.invalid }
        if !row.isEmpty || !cell.isEmpty { row.append(cell); rows.append(row) }
        return rows
    }

    static func xml(_ input: String, defaultType: ProxyType) throws -> [ImportedProxy] {
        let lower = input.lowercased()
        guard !lower.contains("<!doctype"), !lower.contains("<!entity") else { throw ProxyImportError.invalid }
        let reader = ProxyXMLReader(defaultType: defaultType)
        let parser = XMLParser(data: Data(input.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.failure == nil else { throw reader.failure ?? ProxyImportError.invalid }
        guard !reader.proxies.isEmpty else { throw ProxyImportError.empty }
        return reader.proxies
    }

    fileprivate static func makeXMLProxy(_ attributes: [String: String], defaultType: ProxyType) throws -> ImportedProxy {
        var values: [String: String] = [:]
        for (field, value) in attributes {
            let normalized = key(field)
            guard values.updateValue(value, forKey: normalized) == nil else { throw ProxyImportError.invalid }
        }
        let type = try ProxyImport.specifiedType(values["type"], defaultType: defaultType)
        return try ProxyImport.item(host: values["host"] ?? "", port: values["port"] ?? "",
                                    username: values["username"] ?? "", password: values["password"] ?? "",
                                    type: type, name: values["name"] ?? "")
    }
}

private final class ProxyXMLReader: NSObject, XMLParserDelegate {
    let defaultType: ProxyType
    var proxies: [ImportedProxy] = []
    var failure: ProxyImportError?
    private var current: [String: String]?
    private var field: String?
    private var content = ""
    init(defaultType: ProxyType) { self.defaultType = defaultType }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let element = elementName.lowercased()
        if element == "proxy" {
            guard current == nil else { failure = .invalid; parser.abortParsing(); return }
            current = attributes
        } else if current != nil {
            guard field == nil else { failure = .invalid; parser.abortParsing(); return }
            field = element; content = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field != nil { content += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if field != nil, let text = String(data: CDATABlock, encoding: .utf8) { content += text }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        if element == "proxy", let attributes = current {
            do { proxies.append(try ProxyImportStructured.makeXMLProxy(attributes, defaultType: defaultType)) }
            catch { failure = (error as? ProxyImportError) ?? .invalid; parser.abortParsing() }
            current = nil
            if proxies.count > 200 { failure = .tooLarge; parser.abortParsing() }
        } else if field == element, current != nil {
            guard current?[element] == nil else { failure = .invalid; parser.abortParsing(); return }
            current?[element] = content.trimmingCharacters(in: .whitespacesAndNewlines)
            field = nil; content = ""
        }
    }
}
