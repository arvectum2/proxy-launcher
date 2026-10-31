import Foundation

/// Conservative first-party discovery. This does not authorize routing changes:
/// callers must show candidates to the user before adding exclusions.
enum SiteDependencyDiscovery {
    static let maxHTMLBytes = 512_000
    static let maxCandidates = 24

    /// Resource Timing exposes requests issued by scripts, CSS, fonts and fetch,
    /// which are not necessarily represented in the final HTML DOM.
    static func resourceCandidates(urls: [String], for site: String) -> [String] {
        guard let normalized = try? SiteExclusionPolicy.normalize(site),
              normalized.contains("."), !normalized.contains(":") else { return [] }
        let apex = normalized.hasPrefix("www.") ? String(normalized.dropFirst(4)) : normalized
        var found = Set<String>()
        for raw in urls.prefix(512) {
            guard raw.count <= 2048, let components = URLComponents(string: raw),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  let host = components.host?.lowercased(),
                  (host == apex || host.hasSuffix("." + apex)),
                  (try? SiteExclusionPolicy.normalize(host)) == host else { continue }
            found.insert(host)
            if found.count >= maxCandidates { break }
        }
        return found.sorted()
    }

    static func candidates(html: String, for site: String) -> [String] {
        guard let root = try? SiteExclusionPolicy.normalize(site),
              !root.isEmpty, !root.contains(":") else { return [] }
        let apex = root.hasPrefix("www.") ? String(root.dropFirst(4)) : root
        let text = String(html.prefix(maxHTMLBytes))
        let pattern = #"(?i)(?:src|href|action|poster|data-src)\s*=\s*["'](https?:)?//([^/\s"'?#:]+)(?=[/\s"'?#]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var found = Set<String>()
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard match.range(at: 2).location != NSNotFound else { continue }
            let host = ns.substring(with: match.range(at: 2)).lowercased()
            // Only exact host or subdomains of the requested site; never
            // implicitly route analytics, CDNs or unrelated third parties direct.
            guard host == apex || host.hasSuffix("." + apex),
                  let normalized = try? SiteExclusionPolicy.normalize(host),
                  normalized == host else { continue }
            found.insert(host)
            if found.count >= maxCandidates { break }
        }
        return found.sorted()
    }
}
