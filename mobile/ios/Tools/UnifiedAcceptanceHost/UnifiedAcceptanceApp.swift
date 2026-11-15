// Separate unsigned QA target. No production App or automatic VPN actions.
import SwiftUI
import NetworkExtension
import Foundation

@MainActor final class UnifiedAcceptanceModel:ObservableObject {
    static let launchFlag="--apl-explicit-unified-qa"
    @Published private(set) var status="Not armed. No VPN action."
    @Published private(set) var busy=false
    @Published private(set) var armed=false
    @Published var quiescence=false
    private var input:UnifiedSyntheticHostInput?
    private var used=false
    private var cancelled=false
    private var generation=UUID()
    private let directory=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
    private var approvedLaunch:Bool {ProcessInfo.processInfo.arguments.contains(Self.launchFlag)}
    func arm() {
        guard approvedLaunch,!busy,!armed,!used,!cancelled else{return}
        do {
            let path=directory.appendingPathComponent("unified-qa-input.json")
            let attrs=try path.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard attrs.isRegularFile==true,attrs.isSymbolicLink==false,let size=attrs.fileSize,(1...8192).contains(size) else{throw NativeSyntheticProductControlHost.Failure.invalidState}
            let f=try FileHandle(forReadingFrom:path);defer{try? f.close()}
            let data=try f.read(upToCount:8193) ?? Data()
            guard data.count<=8192 else{throw NativeSyntheticProductControlHost.Failure.invalidState}
            let decoded=try JSONDecoder().decode(UnifiedSyntheticHostInput.self,from:data)
            guard decoded.valid else{throw NativeSyntheticProductControlHost.Failure.invalidState}
            try FileManager.default.removeItem(at:path)
            input=decoded;armed=true;status="Input consumed: \(decoded.kind.rawValue) / \(decoded.probe) / \(decoded.mode). Confirm isolated process and manager separately."
        } catch {status="Input rejected. No VPN action."}
    }
    func invalidate() {
        cancelled=true;generation=UUID();input=nil;armed=false;quiescence=false
        if !busy {status="Disarmed. Any attempted VPN requires explicit reconciliation."}
    }
    func execute() async {
        guard approvedLaunch,armed,quiescence,!busy,!used,!cancelled,let input else{return}
        let token=generation
        busy=true;used=true;armed=false;quiescence=false;self.input=nil
        defer{busy=false}
        var host:NativeSyntheticProductControlHost?
        do {
            let all=try await NETunnelProviderManager.loadAllFromPreferences()
            guard generation==token,!cancelled else{throw NativeSyntheticProductControlHost.Failure.invalidState}
            let owned=all.compactMap{try? NativeSyntheticProductControlHost(manager:$0,input:input)}
            guard owned.count==1,let current=owned.first else{throw NativeSyntheticProductControlHost.Failure.unowned}
            host=current;status="Submitting one isolated synthetic test."
            try await current.submit(externalQuiescenceConfirmed:true,stillAuthorized:{self.generation==token && !self.cancelled})
            guard generation==token,!cancelled else{throw NativeSyntheticProductControlHost.Failure.invalidState}
            try await current.observeSetup()
            guard generation==token,!cancelled else{throw NativeSyntheticProductControlHost.Failure.invalidState}
            try await current.probe()
            try await current.drainAndReconcile()
            guard generation==token,!cancelled else{throw NativeSyntheticProductControlHost.Failure.invalidState}
            let result=try JSONEncoder().encode(current.receipt())
            let path=directory.appendingPathComponent("unified-qa-receipt-\(input.runID.uuidString).json")
            try result.write(to:path,options:[.withoutOverwriting,.completeFileProtection])
            status="Host receipt saved; independent peer verification required."
        } catch {
            if let host,host.attempted,!host.off {
                do {try await host.drainAndReconcile();status="Test incomplete; exact drain and OS-off reconciled."}
                catch {status="Test incomplete; drain or OS-off unconfirmed. Stop only the isolated test VPN under operator supervision."}
            } else {status="Test incomplete; no acceptance receipt."}
        }
    }
}

@main struct UnifiedAcceptanceApp:App {
    @StateObject private var model=UnifiedAcceptanceModel()
    @Environment(\.scenePhase) private var phase
    var body:some Scene {
        WindowGroup {
            VStack(alignment:.leading,spacing:16) {
                Text("APL Unified QA").font(.title2)
                Text("Unsigned research candidate. Not a release. Only an explicitly authorized isolated test may run.")
                Text(model.status).font(.footnote)
                Button("Read and consume test input"){model.arm()}.disabled(model.busy || model.armed)
                Toggle("Independent process and manager quiescence confirmed",isOn:$model.quiescence).disabled(!model.armed || model.busy)
                Button("Run one synthetic test"){Task {await model.execute()}}.disabled(!model.armed || !model.quiescence || model.busy)
                Button("Disarm"){model.invalidate()}.disabled(model.busy)
            }.padding().onChange(of:phase){if $0 == .background {model.invalidate()}}
        }
    }
}
