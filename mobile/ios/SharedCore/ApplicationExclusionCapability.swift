import Foundation

public enum IOSApplicationExclusionMode: String, Codable, Equatable {
    case consumerPacketTunnel
    case managedPerAppVPN
}

public struct IOSApplicationExclusionCapability: Equatable {
    public let mode: IOSApplicationExclusionMode

    public init(mode: IOSApplicationExclusionMode) {
        self.mode = mode
    }

    public var canSelectInstalledApplications: Bool {
        mode == .managedPerAppVPN
    }

    public var canEnforcePerApplicationRouting: Bool {
        mode == .managedPerAppVPN
    }

    public var requiresDeviceManagement: Bool {
        true
    }

    public var userFacingSummary: String {
        switch mode {
        case .consumerPacketTunnel:
            return "На обычном iPhone iOS не разрешает приложению выбирать другие установленные приложения и исключать их из Packet Tunnel. Эта возможность доступна только для управляемых устройств (MDM / Per-App VPN)."
        case .managedPerAppVPN:
            return "Исключения приложений управляются профилем MDM / Per-App VPN."
        }
    }
}
