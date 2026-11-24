// Standalone unsigned QA host. Not a production target.
// No automatic VPN changes on launch. Only the separately identified lab
// manager may be created, started or removed on explicit button actions.
import Foundation
import SwiftUI
import NetworkExtension
import Network

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
    #if APL_PROVIDER_DIRECT_QA
    private static let marker = "APL provider-direct synthetic QA v1"
    #else
    private static let marker = "APL isolated synthetic QA v1"
    #endif
    @Published var fixture = ""
    @Published var nonce = ""
    @Published private(set) var status = "Not started"
    @Published private(set) var busy = false
    private var manager: NETunnelProviderManager?
    private var automated = false
    private var nativeControlQA = false
    private var nativeControl: NativeControlLabHost?
    private var runID: String?
    private var transport = "vless"
    private var probeKind = "tcp4"
    private var exitChallenge: Int?
    private var probeCode = -999
    private var counters:[String:Int] = [:]
    #if APL_PROVIDER_DIRECT_QA
    private var providerDirectReceipt:[String:Bool] = [:]
    #endif
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
        struct Input: Decodable { let fixture:String; let nonce:String; let runID:String; let retainProfile:Bool?; let exitChallenge:Int?; let transport:String?; let probeKind:String?; let nativeControlQA:Bool? }
        guard let raw=try? Data(contentsOf:input),raw.count<=4096,
              let request=try? JSONDecoder().decode(Input.self,from:raw),
              UUID(uuidString:request.runID) != nil else { return }
        try? FileManager.default.removeItem(at:input)
        runID=request.runID;stage("inputConsumed")
        #if APL_PROVIDER_DIRECT_QA
        if request.fixture=="inspect-only" {
            let report=await inspectProviderManagers(runID:request.runID)
            if let data=try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys) {
                try? data.write(to:output,options:.atomic)
            }
            return
        }
        #endif
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
        transport=request.transport ?? "vless"
        probeKind=request.probeKind ?? "tcp4"
        #if APL_PROVIDER_DIRECT_QA
        #if APL_PROVIDER_FULL_ROUTE_QA
        guard (transport=="vless-product-direct" && FixedWitnessKind(rawValue:probeKind) != nil) || request.fixture=="cleanup-only" else{return}
        #else
        guard (transport == "vless-product-direct" && probeKind == "tcp4") || request.fixture=="cleanup-only" else {return}
        #endif
        #else
        guard (transport == "vless" && probeKind == "tcp4") ||
            (transport == "wg-dual" && ["tcp4","tcp6","udp4","udp6"].contains(probeKind)) else {return}
        #endif
        nativeControlQA = request.nativeControlQA == true
        #if APL_PROVIDER_DIRECT_QA
        guard !nativeControlQA,request.exitChallenge == nil,request.retainProfile != true else{return}
        #endif
        guard !nativeControlQA || request.exitChallenge == nil else {return}
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
                if let data, let parsed=try JSONSerialization.jsonObject(with:data) as? [String:Int] {counters.merge(parsed){old,_ in old}}
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
        var nativeAccepted = false
        if let nativeControl { nativeAccepted = await nativeControl.finish() }
        stage("cleanupBegin")
        if request.retainProfile == true && request.fixture != "cleanup-only" {
            await stopKeepingProfile()
        } else { await stopAndRemoveExplicitly() }
        stage("cleanupEnd")
        let retained=status == "Owned lab profile retained; VPN OFF"
        let cleaned=status == "Owned lab profile removed" || status == "No owned lab manager"
        var result:[String:Any]=["runID":request.runID,"connected":connected,
                                "receipt":receipt,"cleaned":cleaned,"retainedOff":retained,
                                "nativeExitConfirmed":nativeExitConfirmed,"probeCode":probeCode,"counters":counters]
        #if APL_PROVIDER_DIRECT_QA
        result["providerDirectReceipt"]=providerDirectReceipt
        #endif
        if nativeControlQA {
            result["nativeControlAccepted"] = nativeAccepted
            if let nativeControl { for (key,value) in nativeControl.report { result[key] = value } }
        }
        if let data=try? JSONSerialization.data(withJSONObject:result) {
            try? data.write(to:output,options:.atomic)
        }
        print("APL_PHYSICAL_NATIVE_QA_CONNECTED_\(connected)_RECEIPT_\(receipt)_CLEANED_\(cleaned)")
    }

    #if APL_PROVIDER_DIRECT_QA
    // Accept coexistence only with a known historical lab shape in a disabled,
    // disconnected, credential-free state. Never adopt, edit or remove it.
    private func historicalDormantKind(_ item:NETunnelProviderManager)->String? {
        guard let p=item.protocolConfiguration as? NETunnelProviderProtocol,
              p.providerBundleIdentifier==Self.bundle,!item.isEnabled,
              item.connection.status == .disconnected,
              !item.isOnDemandEnabled,(item.onDemandRules ?? []).isEmpty,
              p.username==nil,p.passwordReference==nil,p.identityReference==nil,
              p.identityData==nil,p.identityDataPassword==nil,p.proxySettings==nil,
              !p.includeAllNetworks,!p.enforceRoutes,
              let config=p.providerConfiguration else{return nil}
        if Set(config.keys)==["labOwner"],let marker=config["labOwner"] as? String {
            if marker=="APL isolated synthetic QA v1",item.localizedDescription==marker,
                p.serverAddress=="APL synthetic lab only" {return "priorXrayLab"}
            if marker=="APL standalone AWG synthetic QA v1",item.localizedDescription==marker,
                p.serverAddress=="Synthetic AWG only" {return "priorAWGLab"}
        }
        // stage_nativeqa_isolated.py rebinds the actual product controller
        // to this lab-only bundle ID. Its exact two-key owner config is safe
        // to preserve, not permission to assume ownership or erase Keychain.
        guard Set(config.keys)==["aplNativeMode","aplNativeOwner"],
              let mode=config["aplNativeMode"] as? String,
              let owner=config["aplNativeOwner"] as? String,UUID(uuidString:owner) != nil else{return nil}
        let name:String
        switch mode {
        case "native-product-start-v1":name="APL Native Product"
        case "native-runtime-review-v1":name="APL Native Runtime Review"
        case "credential-validation-v1":name="APL Native Credential Validation"
        default:return nil
        }
        return item.localizedDescription==name && p.serverAddress==name ? mode:nil
    }
    private func inspectProviderManagers(runID:String) async -> [String:Any] {
        var report:[String:Any]=["runID":runID,"readOnly":true]
        do {
            let all=try await NETunnelProviderManager.loadAllFromPreferences()
            let related=all.filter{($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier==Self.bundle}
            let owned=related.filter(isOwned)
            report["visibleManagers"]=all.count
            report["relatedManagers"]=related.count
            report["ownedManagers"]=owned.count
            report["ownedEnabled"]=owned.filter{$0.isEnabled}.count
            report["ownedOnDemand"]=owned.filter{$0.isOnDemandEnabled}.count
            report["otherActive"]=all.filter{!isOwned($0) && $0.connection.status != .disconnected && $0.connection.status != .invalid}.count
            report["relatedStates"]=related.map{$0.connection.status.rawValue}
            report["relatedEnabled"]=related.filter{$0.isEnabled}.count
            report["historicalDormantKinds"]=related.map{historicalDormantKind($0) ?? "unclassified"}
            report["knownDormantCount"]=related.filter{historicalDormantKind($0) != nil}.count
        } catch {
            report["errorCode"]=(error as NSError).code
            report["loadFailed"]=true
        }
        return report
    }
    #endif
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
        #if APL_PROVIDER_DIRECT_QA
        let owned=named.filter(isOwned),preserved=named.filter{!isOwned($0)}
        guard owned.count<=1,preserved.count<=1,
              preserved.allSatisfy({historicalDormantKind($0) != nil}) else{throw LabHostError.conflict}
        #else
        guard named.count <= 1, named.allSatisfy(isOwned) else { throw LabHostError.conflict }
        #endif
        // Never displace an existing owner or unrelated VPN.
        guard all.filter({ !isOwned($0) }).allSatisfy({
            $0.connection.status == .disconnected || $0.connection.status == .invalid
        }) else { throw LabHostError.otherVPN }
        #if APL_PROVIDER_DIRECT_QA
        if let existing=owned.first{return existing}
        #else
        if let existing = named.first { return existing }
        #endif
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
            #if APL_PROVIDER_DIRECT_QA
            if let labError=error as? LabHostError {
                switch labError {
                case .conflict:stage("prepareConflict")
                case .otherVPN:stage("prepareOtherVPN")
                case .fixture:stage("prepareFixture")
                }
            } else {
                stage("prepareSystemError-"+String((error as NSError).code))
            }
            #else
            stage("prepareFailed")
            #endif
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
            if transport == "wg-dual" {
                _ = try XrayWireGuardLabConfig.prepare(link,port:39879,dual:true,physical:true)
            } else {
                let parsed = try VLESSRealityShareLink.parse(link)
                guard parsed.serverHost == "192.168.1.80", parsed.serverPort == 39882,
                      parsed.serverName == "example.com" else {throw LabHostError.fixture}
            }
            guard let item = try await labManager(create:false),
                  isOwned(item), item.isEnabled, !item.isOnDemandEnabled,
                  item.connection.status == .disconnected else { throw LabHostError.conflict }
            manager = item
            stage("startTunnelBegin")
            var options:[String:NSObject]=[
                "aplNativeSyntheticQA":"explicit-lab-v1" as NSString,
                "aplSyntheticLink":link as NSString,
                "aplLabTransport":transport as NSString
            ]
            #if APL_PROVIDER_DIRECT_QA
            guard transport=="vless-product-direct",nonce.utf8.count==40,
                  nonce.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else {throw LabHostError.fixture}
            options["aplProviderNonce"]=nonce as NSString
            #if APL_PROVIDER_FULL_ROUTE_QA
            guard FixedWitnessKind(rawValue:probeKind) != nil else{throw LabHostError.fixture}
            options["aplFixedWitnessKind"]=probeKind as NSString
            #endif
            #endif
            if let exitChallenge {options["aplLabExitChallenge"]=NSNumber(value:exitChallenge)}
            if nativeControlQA {
                let native = try NativeControlLabHost(manager:item, transport:transport == "wg-dual" ? .wireGuard : .vlessReality, options:options, externalQuiescenceConfirmed:true)
                nativeControl = native
                try await native.start()
            } else { try item.connection.startVPNTunnel(options:options) }
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
        #if APL_PROVIDER_DIRECT_QA
        guard transport=="vless-product-direct",let session=manager.connection as? NETunnelProviderSession else{return}
        #if APL_PROVIDER_SCOPED_TUN_QA
        // A fixed raw TCP probe avoids the URLSession ATS preflight failure.
        // The system routing table, not an explicit interface, selects TUN.
        #if APL_PROVIDER_FULL_ROUTE_QA
        guard let kind=FixedWitnessKind(rawValue:probeKind) else{return}
        let rawResult=await Task.detached(priority:.userInitiated){
            kind.udp ? FixedUDPWitness.run(value,kind:kind):ScopedTCPWitness.run(value,kind:kind)
        }.value
        #else
        let rawResult=await Task.detached(priority:.userInitiated){ScopedTCPWitness.run(value)}.value
        #endif
        counters.merge(rawResult.counters){old,_ in old}
        let hostExact=rawResult.exact && manager.connection.status == .connected
        #endif
        let direct:Data?=await withCheckedContinuation { continuation in
            let gate=LabMessageGate(continuation)
            DispatchQueue.global().asyncAfter(deadline:.now()+9){gate.finish(nil)}
            do {try session.sendProviderMessage(Data("apl-provider-direct-v1".utf8)){gate.finish($0)}}
            catch {gate.finish(nil)}
        }
        if let direct,let parsed=try? JSONSerialization.jsonObject(with:direct) as? [String:Bool] {
            providerDirectReceipt=parsed
        }
        #if APL_PROVIDER_SCOPED_TUN_QA
        providerDirectReceipt["hostExactHTTPReceipt"]=hostExact
        #if APL_PROVIDER_FULL_ROUTE_QA
        let expectedRoute=providerDirectReceipt["fullRouteSyntheticGuard"]==true && providerDirectReceipt["scopedRouteOnly"]==false && providerDirectReceipt["witness_"+kind.rawValue]==true
        #else
        let expectedRoute=providerDirectReceipt["scopedRouteOnly"]==true
        #endif
        let good=hostExact && expectedRoute && providerDirectReceipt["providerProcess"]==true &&
            providerDirectReceipt["rustTUNStarted"]==true && providerDirectReceipt["rustDrainConfirmed"]==true &&
            providerDirectReceipt["nativeStopConfirmed"]==true
        #else
        let good=providerDirectReceipt["exactHTTPReceipt"]==true && providerDirectReceipt["providerProcess"]==true && providerDirectReceipt["rustTUNStarted"]==false && providerDirectReceipt["nativeStopConfirmed"]==true
        #endif
        probeCode=good ? 200 : -1001
        status=good ? "Exact response received; verify independent server receipt" : "Probe failed"
        return
        #else
        if probeKind == "udp4" || probeKind == "udp6" {
            let destination=probeKind == "udp4" ? "198.51.100.77" : "2001:db8:77::77"
            let request=Data(("APL_UDP:"+value).utf8)
            let reply=await udpProbe(host:destination,request:request)
            let good=reply == Data(("APL_RECEIPT:"+value).utf8) && manager.connection.status == .connected
            probeCode=good ? 200 : -1001
            status=good ? "Exact response received; verify independent server receipt" : "Probe failed"
            return
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 6
        cfg.connectionProxyDictionary = [:]
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        let session = URLSession(configuration:cfg,delegate:NoLabRedirect(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        do {
            let address=probeKind == "tcp6" ? "[2001:db8:77::77]" : "198.51.100.77"
            guard let url = URL(string:"http://"+address+":39883/"+value) else { return }
            let (data,response) = try await session.data(from:url)
            probeCode=(response as? HTTPURLResponse)?.statusCode ?? -998
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data == Data(("APL_RECEIPT:"+value).utf8),
                  manager.connection.status == .connected else {
                status = "Probe failed"; return
            }
            status = "Exact response received; verify independent server receipt"
        } catch { probeCode=(error as NSError).code;status = "Probe failed" }
        #endif
    }

    private func udpProbe(host:String,request:Data) async -> Data? {
        let connection=NWConnection(host:NWEndpoint.Host(host),port:39883,using:.udp)
        let queue=DispatchQueue(label:"apl.lab.udp.probe")
        let result:Data?=await withCheckedContinuation { continuation in
            let gate=LabMessageGate(continuation)
            connection.stateUpdateHandler={ state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler=nil
                    connection.send(content:request,completion:.contentProcessed { error in
                        guard error == nil else {gate.finish(nil);return}
                        connection.receiveMessage { data,_,_,error in
                            gate.finish(error == nil ? data : nil)
                        }
                    })
                case .failed,.cancelled:gate.finish(nil)
                default:break
                }
            }
            queue.asyncAfter(deadline:.now()+5) {gate.finish(nil);connection.cancel()}
            connection.start(queue:queue)
        }
        connection.cancel()
        return result
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
