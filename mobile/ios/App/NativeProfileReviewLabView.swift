#if DEBUG && APL_NATIVE_PROFILE_REVIEW && targetEnvironment(simulator)
import SwiftUI
import UniformTypeIdentifiers

/// Simulator-only screen; no real store, VPN manager or account.
@MainActor struct NativeProfileReviewLabView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session=NativeProfileReviewSession()
    @State private var kind:NativeCredentialRecord.Kind = .wireGuard
    @State private var summary:NativeRestoreReview.Summary?
    @State private var password=""
    @State private var repeatedPassword=""
    @State private var file:Data?
    @State private var choosing=false
    @State private var backupMode=false
    @State private var exporting=false
    @State private var showExporter=false
    @State private var document:RehearsalBackupDocument?
    @State private var total=0
    @State private var failed=false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Simulator QA only. Use synthetic test files. Nothing is saved to the profile library or connected to VPN.")
                    Text("Temporary profiles: \(total)")
                }
                Section("Configuration review") {
                    Picker("Protocol",selection:$kind) {
                        Text("WireGuard").tag(NativeCredentialRecord.Kind.wireGuard)
                        Text("AmneziaWG 1").tag(NativeCredentialRecord.Kind.amneziaWG1)
                        Text("VLESS Reality").tag(NativeCredentialRecord.Kind.vlessReality)
                    }.onChange(of:kind){_ in resetReview()}
                    Button("Choose synthetic configuration text file") { resetReview();backupMode=false;choosing=true }
                }
                Section("Encrypted backup") {
                    Button("Choose synthetic backup JSON") { resetReview();backupMode=true;choosing=true }
                    if file != nil {
                        SecureField("Backup password",text:$password).textContentType(.password)
                        Button("Review backup",action:reviewBackup).disabled(password.isEmpty)
                    }
                    Button("Prepare encrypted export") {resetReview();exporting=true}.disabled(total==0)
                    if exporting {
                        SecureField("New password",text:$password).textContentType(.newPassword)
                        SecureField("Repeat password",text:$repeatedPassword).textContentType(.newPassword)
                        Button("Encrypt",action:encrypt).disabled(password.count<12 || password != repeatedPassword)
                    }
                }
                if let summary {
                    Section("Review — counts only") {
                        Text("WireGuard: \(summary.wireGuard)")
                        Text("AmneziaWG 1: \(summary.amneziaWG1)")
                        Text("VLESS Reality: \(summary.vless)")
                        Button("Add to test memory only") { accept(summary) }
                        Button("Cancel",role:.cancel){resetReview()}
                    }
                }
                if failed { Text("Review failed. No new records added.").foregroundStyle(.red) }
            }
            .navigationTitle("Native profiles · QA")
            .toolbar {ToolbarItem(placement:.cancellationAction){Button("Close"){dismiss()}}}
        }
        .fileImporter(isPresented:$choosing,allowedContentTypes:[.data],allowsMultipleSelection:false, onCompletion:readFile)
        .fileExporter(isPresented:$showExporter,document:document,contentType:.json,defaultFilename:"APL-Native-QA-Encrypted"){_ in document=nil}
        .onDisappear {resetReview();session.clear();document=nil;total=0}
    }
    private func resetReview(){session.cancelReview();summary=nil;password="";repeatedPassword="";file=nil;exporting=false;failed=false}
    private func fail(){resetReview();failed=true}
    private func readFile(_ result:Result<[URL],Error>){
        do {
            guard let url=try result.get().first else{return}
            let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
            if backupMode {file=try ProfileBackupCodec.readEncryptedFile(at:url)} else {
                let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
                var bytes=Data()
                while bytes.count<=NativeCredentialRecord.maxBytes {
                    let part=try handle.read(upToCount:NativeCredentialRecord.maxBytes+1-bytes.count) ?? Data()
                    if part.isEmpty{break};bytes.append(part)
                }
                guard bytes.count<=NativeCredentialRecord.maxBytes,let raw=String(data:bytes,encoding:.utf8) else {throw ProfileBackupError.invalidFile}
                summary=try session.previewSource(raw,kind:kind)
            }
        } catch {fail()}
    }
    private func reviewBackup(){guard let file else{return};let p=password;resetReview();do{summary=try session.previewBackup(file,password:p)}catch{fail()}}
    private func accept(_ value:NativeRestoreReview.Summary){do{total=try session.addToRehearsal(value).total;resetReview()}catch{fail()}}
    private func encrypt(){guard password==repeatedPassword else{fail();return};let p=password;resetReview();do{document=RehearsalBackupDocument(bytes:try session.encryptedBackup(password:p));showExporter=true}catch{fail()}}
}
private struct RehearsalBackupDocument:FileDocument {
    static var readableContentTypes:[UTType]{[.json]}
    let bytes:Data
    init(bytes:Data){self.bytes=bytes}
    init(configuration:ReadConfiguration)throws{guard let b=configuration.file.regularFileContents,b.count<=ProfileBackupCodec.maxFileBytes else{throw ProfileBackupError.invalidFile};bytes=b}
    func fileWrapper(configuration:WriteConfiguration)throws->FileWrapper{FileWrapper(regularFileWithContents:bytes)}
}
#endif
