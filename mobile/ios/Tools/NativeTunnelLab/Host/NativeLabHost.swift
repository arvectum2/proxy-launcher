// Standalone unsigned QA host. Not a production target.
// No automatic VPN changes on launch. Only the separately identified lab
// manager may be created, started or removed on explicit button actions.
import Foundation
import SwiftUI
import NetworkExtension

private final class NoLabRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor final class NativeLabHostModel: ObservableObject {
    private static let bundle = "ru.arvectum.proxylauncher.lab.nativeqa.PacketTunnel"
    private static let marker = "APL isolated synthetic QA v1"
    @Published var fixture = ""
    @Published var nonce = ""
    @Published private(set) var status = "Not started"
    @Published private(set) var busy = false
    private var manager: NETunnelProviderManager?

    private func isOwned(_ item: NETunnelProviderManager) -> Bool {
        guard let proto = item.protocolConfiguration as? NETunnelProviderProtocol else { return false }
        return proto.providerBundleIdentifier == Self.bundle &&
            proto.providerConfiguration?["labOwner"] as? String == Self.marker
    }

    private func labManager(create: Bool) async throws -> NETunnelProviderManager? {
        let all = try await NETunnelProviderManager.loadAllFromPreferences()
        let named = all.filter {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.bundle
        }
        guard named.count <= 1, named.allSatisfy(isOwned) else { throw LabHostError.conflict }
        // Never displace an existing owner or unrelated VPN.
        guard all.filter({ !isOwned($0) }).allSatisfy({
            $0.connection.status == .disconnected || $0.connection.status == .invalid
        }) else { throw LabHostError.otherVPN }
        if let existing = named.first { return existing }
        guard create else { return nil }
        let item = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.bundle
        proto.serverAddress = "APL synthetic lab only"
        proto.providerConfiguration = ["labOwner": Self.marker]
        item.protocolConfiguration = proto
        item.localizedDescription = Self.marker
        item.isEnabled = true
        item.isOnDemandEnabled = false
        try await item.saveToPreferences()
        try await item.loadFromPreferences()
        guard isOwned(item) else { throw LabHostError.conflict }
        return item
    }

    func startExplicitly() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        // Only the fixed, synthetic LAN peer accepted by the extension.
        // Text held in RAM; never put credential material in preferences.
        let link = fixture
        fixture = ""
        manager = nil
        do {
            let parsed = try VLESSRealityShareLink.parse(link)
            guard parsed.serverHost == "192.168.1.80", parsed.serverPort == 39882,
                  parsed.serverName == "example.com" else { throw LabHostError.fixture }
            guard let item = try await labManager(create:true),
                  isOwned(item), item.isEnabled, !item.isOnDemandEnabled,
                  item.connection.status == .disconnected else { throw LabHostError.conflict }
            manager = item
            try item.connection.startVPNTunnel(options:[
                "aplNativeSyntheticQA":"explicit-lab-v1" as NSString,
                "aplSyntheticLink":link as NSString
            ])
            status = "Start requested; awaiting iOS"
            // Actual .connected is distinct from startVPNTunnel returning.
            for _ in 0..<100 {
                if item.connection.status == .connected {
                    status = "iOS connected (native receipt still required)"
                    return
                }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            item.connection.stopVPNTunnel()
            status = "Start timeout; stop requested"
        } catch {
            if let manager, isOwned(manager) { manager.connection.stopVPNTunnel() }
            status = "Start refused or failed"
        }
    }

    func probeExplicitly() async {
        guard !busy, let manager, isOwned(manager),
              manager.connection.status == .connected else { return }
        let value = nonce.lowercased()
        nonce = ""
        guard value.utf8.count == 40, value.utf8.allSatisfy({
            (48...57).contains($0) || (97...102).contains($0)
        }) else { status = "Invalid test nonce"; return }
        busy = true
        defer { busy = false }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 6
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        let session = URLSession(configuration:cfg,delegate:NoLabRedirect(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        do {
            guard let url = URL(string:"http://198.51.100.77:39883/"+value) else { return }
            let (data,response) = try await session.data(from:url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data == Data(("APL_RECEIPT:"+value).utf8),
                  manager.connection.status == .connected else {
                status = "Probe failed"; return
            }
            status = "Exact response received; verify independent server receipt"
        } catch { status = "Probe failed" }
    }

    func stopAndRemoveExplicitly() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard let item = try await labManager(create:false), isOwned(item) else {
                status = "No owned lab manager"; return
            }
            item.connection.stopVPNTunnel()
            for _ in 0..<100 {
                if item.connection.status == .disconnected || item.connection.status == .invalid {
                    try await item.removeFromPreferences()
                    manager = nil
                    status = "Owned lab profile removed"
                    return
                }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            status = "Stop not confirmed; profile retained"
        } catch { status = "Cleanup refused or failed" }
    }

    private enum LabHostError: Error { case conflict, otherVPN, fixture }
}

@main struct APLNativeLabHost: App {
    @StateObject private var model = NativeLabHostModel()
    var body: some Scene {
        WindowGroup {
            Form {
                Text("Isolated synthetic transport QA")
                SecureField("Ephemeral synthetic VLESS link",text:$model.fixture)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Create isolated profile and start") {
                    Task { await model.startExplicitly() }
                }
                TextField("40-character test nonce",text:$model.nonce)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Send exact test request") { Task { await model.probeExplicitly() } }
                Button("Stop and remove isolated profile",role:.destructive) {
                    Task { await model.stopAndRemoveExplicitly() }
                }
                Text(model.status)
            }.disabled(model.busy)
        }
    }
}
