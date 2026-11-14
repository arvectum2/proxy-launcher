// Standalone unsigned QA host. Not a production target.
// No automatic VPN changes on launch. Only the separately identified lab
// manager may be created, started or removed on explicit button actions.
import Foundation
import SwiftUI
import NetworkExtension

private final class LabMessageGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }
    func finish(_ data: Data?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: data)
    }
}

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
    private var automated = false
    private var runID: String?
    private var exitChallenge: Int?
    private var probeCode = -999
    private var counters:[String:Int] = [:]
    private func stage(_ value: String) {
        guard let runID else {return}
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("native-lab-progress.json")
        if let data=try? JSONSerialization.data(withJSONObject:["runID":runID,"stage":value]) {
            try? data.write(to:url,options:.atomic)
        }
    }

    // Explicit device-launch argument + one-shot private synthetic input.
    // No production data, no automatic start on normal launches.
    func runAuthorizedDeviceQA() async {
        guard ProcessInfo.processInfo.arguments.contains("--apl-authorized-native-qa"),
              !automated else { return }
        automated = true
        let documents = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let input = documents.appendingPathComponent("native-lab-input.json")
        let output = documents.appendingPathComponent("native-lab-result.json")
        try? FileManager.default.removeItem(at:output)
        struct Input: Decodable { let fixture:String; let nonce:String; let runID:String; let retainProfile:Bool?; let exitChallenge:Int? }
        guard let raw=try? Data(contentsOf:input),raw.count<=4096,
              let request=try? JSONDecoder().decode(Input.self,from:raw),
              UUID(uuidString:request.runID) != nil else { return }
        try? FileManager.default.removeItem(at:input)
        runID=request.runID;stage("inputConsumed")
        if request.fixture == "prepare-only" {
            await prepareExplicitly()
            let prepared=status == "Lab profile prepared; VPN OFF"
            let result:[String:Any]=["runID":request.runID,"prepared":prepared,"connected":false]
            if let data=try? JSONSerialization.data(withJSONObject:result) {
                try? data.write(to:output,options:.atomic)
            }
            return
        }
        guard request.exitChallenge == nil || (100000...999999).contains(request.exitChallenge!) else {return}
        exitChallenge=request.exitChallenge
        fixture=request.fixture;nonce=request.nonce
        if request.fixture != "cleanup-only" { await startExplicitly() }
        let connected=manager?.connection.status == .connected
        if connected { stage("probeBegin");await probeExplicitly();stage("probeEnd") }
        if connected, let session=manager?.connection as? NETunnelProviderSession {
            do {
                let data: Data? = await withCheckedContinuation { continuation in
                    let gate = LabMessageGate(continuation)
                    DispatchQueue.global().asyncAfter(deadline:.now()+2) { gate.finish(nil) }
                    do {
                        try session.sendProviderMessage(Data("apl-lab-counters-v1".utf8)) { gate.finish($0) }
                    } catch { gate.finish(nil) }
                }
                if let data, let parsed=try JSONSerialization.jsonObject(with:data) as? [String:Int] {counters=parsed}
            } catch {}
        }
        let receipt=status == "Exact response received; verify independent server receipt"
        var nativeExitConfirmed=false
        if #available(iOS 16.0, *), connected, receipt, let challenge=exitChallenge,
           let session=manager?.connection as? NETunnelProviderSession {
            stage("nativeExitRequest")
            let ack:Data? = await withCheckedContinuation { continuation in
                let gate=LabMessageGate(continuation)
                DispatchQueue.global().asyncAfter(deadline:.now()+2) {gate.finish(nil)}
                do {try session.sendProviderMessage(Data(("apl-lab-exit-"+String(challenge)).utf8)) {gate.finish($0)}}
                catch {gate.finish(nil)}
            }
            if ack == Data("exit-requested".utf8) {
                for _ in 0..<80 {
                    if session.status == .disconnected {
                        let response:Data? = await withCheckedContinuation { continuation in
                            let gate=LabMessageGate(continuation)
                            DispatchQueue.global().asyncAfter(deadline:.now()+2) {gate.finish(nil)}
                            session.fetchLastDisconnectError { error in
                                let e=error as NSError?
                                gate.finish(Data((e?.domain == "APL.IsolatedNativeLab" && e?.code == challenge ? "confirmed" : "mismatch").utf8))
                            }
                        }
                        nativeExitConfirmed=response == Data("confirmed".utf8)
                        break
                    }
                    try? await Task.sleep(nanoseconds:100_000_000)
                }
            }
        }
        stage("cleanupBegin")
        if request.retainProfile == true && request.fixture != "cleanup-only" {
            await stopKeepingProfile()
        } else { await stopAndRemoveExplicitly() }
        stage("cleanupEnd")
        let retained=status == "Owned lab profile retained; VPN OFF"
        let cleaned=status == "Owned lab profile removed" || status == "No owned lab manager"
        let result:[String:Any]=["runID":request.runID,"connected":connected,
                                "receipt":receipt,"cleaned":cleaned,"retainedOff":retained,
                                "nativeExitConfirmed":nativeExitConfirmed,"probeCode":probeCode,"counters":counters]
        if let data=try? JSONSerialization.data(withJSONObject:result) {
            try? data.write(to:output,options:.atomic)
        }
        print("APL_PHYSICAL_NATIVE_QA_CONNECTED_\(connected)_RECEIPT_\(receipt)_CLEANED_\(cleaned)")
    }

    private func isOwned(_ item: NETunnelProviderManager) -> Bool {
        guard let proto = item.protocolConfiguration as? NETunnelProviderProtocol else { return false }
        return proto.providerBundleIdentifier == Self.bundle &&
            proto.providerConfiguration?["labOwner"] as? String == Self.marker
    }

    private func labManager(create: Bool) async throws -> NETunnelProviderManager? {
        stage("loadManagersBegin")
        let all = try await NETunnelProviderManager.loadAllFromPreferences()
        stage("loadManagersEnd")
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
        stage("saveLabManagerBegin")
        try await item.saveToPreferences()
        stage("saveLabManagerEnd")
        stage("reloadLabManagerBegin")
        try await item.loadFromPreferences()
        stage("reloadLabManagerEnd")
        guard isOwned(item) else { throw LabHostError.conflict }
        return item
    }

    // Permission-only phase. Never starts the provider and requires no peer.
    func prepareExplicitly() async {
        guard !busy else {return}
        busy=true
        defer {busy=false}
        status="Confirm VPN permission on iPhone"
        do {
            guard let item=try await labManager(create:true), isOwned(item),
                  item.isEnabled, !item.isOnDemandEnabled,
                  item.connection.status == .disconnected else {throw LabHostError.conflict}
            manager=item
            stage("labPreparedOff")
            status="Lab profile prepared; VPN OFF"
        } catch {
            stage("prepareFailed")
            status="Lab profile preparation failed"
        }
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
            guard let item = try await labManager(create:false),
                  isOwned(item), item.isEnabled, !item.isOnDemandEnabled,
                  item.connection.status == .disconnected else { throw LabHostError.conflict }
            manager = item
            stage("startTunnelBegin")
            var options:[String:NSObject]=[
                "aplNativeSyntheticQA":"explicit-lab-v1" as NSString,
                "aplSyntheticLink":link as NSString
            ]
            if let exitChallenge {options["aplLabExitChallenge"]=NSNumber(value:exitChallenge)}
            try item.connection.startVPNTunnel(options:options)
            stage("startTunnelReturned")
            status = "Start requested; awaiting iOS"
            // Actual .connected is distinct from startVPNTunnel returning.
            for _ in 0..<100 {
                if item.connection.status == .connected {
                    stage("iOSConnected")
                    status = "iOS connected (native receipt still required)"
                    return
                }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            item.connection.stopVPNTunnel()
            stage("startTimeout")
            status = "Start timeout; stop requested"
        } catch {
            if let manager, isOwned(manager) { manager.connection.stopVPNTunnel() }
            stage("startFailed")
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
        cfg.connectionProxyDictionary = [:]
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        let session = URLSession(configuration:cfg,delegate:NoLabRedirect(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        do {
            guard let url = URL(string:"http://198.51.100.77:39883/"+value) else { return }
            let (data,response) = try await session.data(from:url)
            probeCode=(response as? HTTPURLResponse)?.statusCode ?? -998
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data == Data(("APL_RECEIPT:"+value).utf8),
                  manager.connection.status == .connected else {
                status = "Probe failed"; return
            }
            status = "Exact response received; verify independent server receipt"
        } catch { probeCode=(error as NSError).code;status = "Probe failed" }
    }

    private func stopKeepingProfile() async {
        do {
            guard let item=try await labManager(create:false),isOwned(item) else {throw LabHostError.conflict}
            if item.connection.status != .disconnected {item.connection.stopVPNTunnel()}
            for _ in 0..<100 {
                if item.connection.status == .disconnected {
                    status="Owned lab profile retained; VPN OFF";return
                }
                try await Task.sleep(nanoseconds:100_000_000)
            }
        } catch {}
        status="Stop not confirmed; profile retained"
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
                    let remaining=try await NETunnelProviderManager.loadAllFromPreferences()
                    guard !remaining.contains(where:isOwned) else {throw LabHostError.conflict}
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
                Button("Prepare isolated VPN profile (OFF)") { Task { await model.prepareExplicitly() } }
                SecureField("Ephemeral synthetic VLESS link",text:$model.fixture)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Start prepared lab profile") {
                    Task { await model.startExplicitly() }
                }
                TextField("40-character test nonce",text:$model.nonce)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Send exact test request") { Task { await model.probeExplicitly() } }
                Button("Stop and remove isolated profile",role:.destructive) {
                    Task { await model.stopAndRemoveExplicitly() }
                }
                Text(model.status)
            }.disabled(model.busy).task { await model.runAuthorizedDeviceQA() }
        }
    }
}
