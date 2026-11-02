import Foundation
import Darwin

/// Bounds an IP-wide NE excluded route when a known, unapproved DNS name
/// resolves to the same address as an approved site. This is not a substitute
/// for per-flow routing: unobserved names, direct IP connections, DoH and
/// third-party hosts can still share an otherwise "uncontested" address.
///
/// All input must be gathered before calling; no persistent permissions or
/// domain approvals are inferred from a DNS record or a shared destination IP.
enum SharedIPRouteGuard {
    struct Plan: Equatable {
        let allowedAddresses: [String]
        let dnsBypass: [String]
        let withheldAddresses: [String]
        let blockedHosts: [String]
    }

    /// Resolve failures for a known non-approved host cannot prove address
    /// independence. Conservatively withhold all domain routes if any known
    /// non-approved host has an unknown/empty answer; upstream connectivity
    /// should be separately excluded and must not use this policy.
    static func plan(
        approved: [String: [String]],
        nonApproved: [String: [String]?]
    ) -> Plan {
        let normalizedApproved = approved.mapValues { addresses in
            Array(Set(addresses.compactMap(canonicalAddress))).sorted()
        }
        let normalizedDenied = nonApproved.mapValues { addresses in
            addresses.map { Array(Set($0.compactMap(canonicalAddress))).sorted() }
        }
        let unverified = normalizedDenied.values.contains { $0 == nil || $0?.isEmpty == true }
        let nonApprovedIPs = Set(normalizedDenied.values.compactMap { $0 }.flatMap { $0 })
        let approvedIPs = Set(normalizedApproved.values.flatMap { $0 })
        let collisions = approvedIPs.intersection(nonApprovedIPs)
        let withheld = unverified ? approvedIPs : collisions
        let safeHosts = normalizedApproved.filter { _, addresses in
            !addresses.isEmpty && addresses.allSatisfy { !withheld.contains($0) }
        }
        return Plan(
            allowedAddresses: Array(Set(safeHosts.values.flatMap { $0 })).sorted(),
            dnsBypass: safeHosts.flatMap { host, addresses in
                addresses.map { "\(host)=\($0)" }
            }.sorted(),
            withheldAddresses: withheld.sorted(),
            blockedHosts: approved.keys.filter { safeHosts[$0] == nil }.sorted()
        )
    }

    /// IPv6 has multiple equivalent textual spellings; compare 128-bit
    /// addresses, never the caller-provided spelling, before creating routes.
    private static func canonicalAddress(_ raw: String) -> String? {
        var v4 = in_addr()
        if raw.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 {
            var output = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            return inet_ntop(AF_INET, &v4, &output, socklen_t(output.count)).map { String(cString: $0) }
        }
        var v6 = in6_addr()
        if raw.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 {
            var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            return inet_ntop(AF_INET6, &v6, &output, socklen_t(output.count)).map { String(cString: $0) }
        }
        return nil
    }
}
