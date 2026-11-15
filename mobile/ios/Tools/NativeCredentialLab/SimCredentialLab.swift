// Simulator-only two-process test. No NE manager, routes or owner data.
#if targetEnvironment(simulator)
import Foundation
import SwiftUI
import CryptoKit

private struct Exchange: Codable {
    let binding: NativeCredentialHandoff.Binding
    let ticket: Data
    let senderPID: Int32
}
private struct Result: Codable {
    let pass: Bool
    let receiverPID: Int32
    let distinctProcess: Bool
    let replayRejected: Bool
    let cleaned: Bool
}
@MainActor private enum Lab {
    static let docs = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
    static let exchangeURL = docs.appendingPathComponent("exchange.json")
    static let resultURL = docs.appendingPathComponent("result.json")
    private static var ran = false
    static func run() {
        guard !ran, ProcessInfo.processInfo.arguments.contains("--synthetic-credential-lab") else { return }
        ran = true
        do {
            let repo=NativeCredentialRepository(items:NativeCredentialKeychain(purpose:.revision))
            let catalog=NativeCredentialCatalog(storage:NativeCredentialCatalogKeychain(),repository:repo,legacyIDs:{[]})
            let handoff=NativeCredentialHandoff.localDeviceValidation()
            if Bundle.main.bundleIdentifier == "ru.arvectum.proxylauncher.credentialqa.sender" {
                guard try catalog.reader.snapshot() == .empty else { throw LabError.invalid }
                let a=Curve25519.KeyAgreement.PrivateKey(),b=Curve25519.KeyAgreement.PrivateKey()
                let source="[Interface]\nPrivateKey=\(a.rawRepresentation.base64EncodedString())\nAddress=10.0.0.2/32, fd00::2/128\nDNS=192.0.2.53\n[Peer]\nPublicKey=\(b.publicKey.rawRepresentation.base64EncodedString())\nAllowedIPs=0.0.0.0/0, ::/0\nEndpoint=192.0.2.42:51820"
                let record=try NativeCredentialRecord.create(profileID:UUID(),expected:.wireGuard,source:source)
                try catalog.save(record,select:true)
                guard let nonce=try catalog.reader.selectionAuthority(record.reference) else {throw LabError.invalid}
                let binding=NativeCredentialHandoff.Binding(reference:record.reference,session:.init(epoch:UUID(),generation:1,provider:"rust-xray"),selectionNonce:nonce)
                let ticket=try handoff.issue(record,binding:binding)
                try JSONEncoder().encode(Exchange(binding:binding,ticket:TransportNativeCodec.encode(ticket),senderPID:getpid())).write(to:exchangeURL,options:.atomic)
            } else if Bundle.main.bundleIdentifier == "ru.arvectum.proxylauncher.credentialqa.receiver" {
                let raw=try Data(contentsOf:exchangeURL); guard raw.count<=4096 else {throw LabError.invalid}
                let e=try JSONDecoder().decode(Exchange.self,from:raw)
                // Binding arrives as a separate expected launch instruction;
                // never derive it by decoding the ticket.
                var receiver=try NativeCredentialReceiver(expected:e.binding,provider:.rustXray)
                let ok=try receiver.consumeForValidation(e.ticket,via:handoff) { route,data in
                    guard case .wireGuard(let wg) = route else {return false}
                    return route.remoteAddress == "192.0.2.42" && route.remotePort == 51820 && !data.isEmpty && wg.excludedRoutes.isEmpty
                }
                var second=try NativeCredentialReceiver(expected:e.binding,provider:.rustXray)
                var replayRejected=false
                do { _ = try second.consumeForValidation(e.ticket,via:handoff) { _,_ in true } } catch { replayRejected=true }
                try catalog.remove(e.binding.reference);try catalog.reconcileRetired()
                let cleaned=try repo.read(e.binding.reference) == nil && catalog.reader.snapshot() == .empty
                let distinct=getpid() != e.senderPID
                try JSONEncoder().encode(Result(pass:ok && distinct && replayRejected && cleaned,receiverPID:getpid(),distinctProcess:distinct,replayRejected:replayRejected,cleaned:cleaned)).write(to:resultURL,options:.atomic)
            } else {throw LabError.invalid}
        } catch {
            // No error description, config bytes or secrets in results.
            try? JSONEncoder().encode(Result(pass:false,receiverPID:getpid(),distinctProcess:false,replayRejected:false,cleaned:false)).write(to:resultURL,options:.atomic)
        }
    }
    enum LabError:Error {case invalid}
}
@main struct SimCredentialLab: App {
    var body: some Scene { WindowGroup { Text("Synthetic credentials QA").task { Lab.run() } } }
}
#endif
