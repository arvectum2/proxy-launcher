import Foundation

enum QuickVPNAction: String, CaseIterable { case connect, disconnect, toggle }
enum QuickVPNConnectionState: Equatable {
    case connected, connecting, disconnected, disconnecting
}
enum QuickVPNDecision: Equatable {
    case connect, disconnect, noChange, busy
}

/// Pure decision logic for explicit user-invoked Shortcuts actions. Never
/// toggles an unknown transition, and does not override app automation state.
enum QuickVPNActionPolicy {
    static func decide(action: QuickVPNAction, state: QuickVPNConnectionState) -> QuickVPNDecision {
        if state == .disconnecting { return .busy }
        switch action {
        case .connect:
            return state == .disconnected ? .connect : .noChange
        case .disconnect:
            return state == .disconnected ? .noChange : .disconnect
        case .toggle:
            return state == .disconnected ? .connect : .disconnect
        }
    }
}
