import Foundation

/// Evidence must come from a separate, controlled QA transport observer.
/// Connection readiness, DNS success or matching CDN IP is NOT proof of path.
enum Smart3TransportEvidence: Equatable {
    case confirmedViaProxy
    case confirmedDirect
    case unknown
    case inferredOnlyFromIP
}

/// Aggregates carry no hostname, address, URL, credential or packet metadata.
struct Smart4DryRunSummary: Equatable {
    let enabled: Bool
    let observed: Int
    let confirmedMatches: Int
    let confirmedMismatches: Int
    let inconclusive: Int
    let proposedDirect: Int
    let proposedProxy: Int
    let capped: Bool
}

/// Pure opt-in QA adapter. No telemetry sink and no PacketTunnel hooks.
/// Source observations are transient and never retained in this value type.
struct Smart4DryRunAudit {
    static let maximumSamples = 256
    private var optedIn = false
    private var observed = 0
    private var confirmedMatches = 0
    private var confirmedMismatches = 0
    private var inconclusive = 0
    private var proposedDirect = 0
    private var proposedProxy = 0
    private var capped = false

    init(optedIn: Bool = false) {
        self.optedIn = optedIn
    }

    mutating func setOptIn(_ value: Bool) {
        // Clear even on re-enabling: never carry prior session history.
        self = Smart4DryRunAudit(optedIn: value)
    }

    /// Host/IP exist only on the stack during the policy evaluation.
    /// Never interpret the IP as an exact-host permission or path proof.
    mutating func observe(
        policy: SmartFlowRoutingPolicy,
        host: String?,
        resolvedIP: String?,
        smart3: Smart3TransportEvidence
    ) {
        guard optedIn else { return }
        guard observed < Self.maximumSamples else {
            capped = true
            return
        }

        let proposed = policy.explain(host: host, resolvedIP: resolvedIP).disposition
        observed += 1
        if proposed == .direct { proposedDirect += 1 }
        else { proposedProxy += 1 }

        let actual: SmartFlowDisposition
        switch smart3 {
        case .confirmedDirect: actual = .direct
        case .confirmedViaProxy: actual = .proxy
        case .unknown, .inferredOnlyFromIP:
            inconclusive += 1
            return
        }

        if proposed == actual { confirmedMatches += 1 }
        else { confirmedMismatches += 1 }
    }

    var summary: Smart4DryRunSummary {
        Smart4DryRunSummary(
            enabled: optedIn,
            observed: observed,
            confirmedMatches: confirmedMatches,
            confirmedMismatches: confirmedMismatches,
            inconclusive: inconclusive,
            proposedDirect: proposedDirect,
            proposedProxy: proposedProxy,
            capped: capped)
    }
}
