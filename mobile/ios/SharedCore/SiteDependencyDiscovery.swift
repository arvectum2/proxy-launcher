import Foundation
import Darwin

/// Conservative first-party discovery. This does not authorize routing changes:
/// callers must show candidates to the user before adding exclusions.
enum SiteDependencyDiscovery {
    static let maxHTMLBytes = 512_000
    static let maxCandidates = 24
    static func isScannableHost(_ host: String) -> Bool {
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
              host.utf8.count <= 253, !host.contains(":"),
              host.utf8.allSatisfy({ $0 < 128 }) else { return false }
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 { return false }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.count <= 63 &&
            label.first != "-" && label.last != "-" &&
            label.utf8.allSatisfy { byte in
                (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 45
            }
        }
    }

    /// Candidates must be new first-party subdomains, not the site itself or its www alias.
    static func additionalCandidates(_ hosts: [String], for site: String, excluding existing: [String] = []) -> [String] {
        guard let normalized = try? SiteExclusionPolicy.normalize(site),
              isScannableHost(normalized) else { return [] }
        let root = normalized.hasPrefix("www.") ? String(normalized.dropFirst(4)) : normalized
        let excluded = Set(existing + [root, "www." + root])
        return Array(Set(hosts.filter { host in
            !excluded.contains(host) && isScannableHost(host) && host.hasSuffix("." + root)
        })).sorted().prefix(maxCandidates).map { $0 }
    }

    /// Resource Timing exposes requests issued by scripts, CSS, fonts and fetch,
    /// which are not necessarily represented in the final HTML DOM.
    static func resourceCandidates(urls: [String], for site: String) -> [String] {
        guard let normalized = try? SiteExclusionPolicy.normalize(site),
              isScannableHost(normalized) else { return [] }
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

    /// Unrelated/sibling domains may host essential assets (e.g. gu-st.ru),
    /// but IP-based split routing can bypass *other* sites on shared CDN IPs.
    /// Return display-only hints; callers must never auto-approve them.
    static func externalCandidates(urls: [String], for site: String) -> [String] {
        guard let root = try? SiteExclusionPolicy.normalize(site),
              isScannableHost(root) else { return [] }
        let apex = root.hasPrefix("www.") ? String(root.dropFirst(4)) : root
        var found = Set<String>()
        for raw in urls.prefix(512) {
            guard raw.count <= 2048,
                  let components = URLComponents(string: raw),
                  components.scheme?.lowercased() == "https",
                  let host = components.host?.lowercased(),
                  isScannableHost(host),
                  host != apex && !host.hasSuffix("." + apex) else { continue }
            found.insert(host)
        }
        return Array(found).sorted().prefix(12).map { $0 }
    }

    static func candidates(html: String, for site: String) -> [String] {
        guard let root = try? SiteExclusionPolicy.normalize(site),
              isScannableHost(root) else { return [] }
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
