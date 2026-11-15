#if DEBUG && APL_NATIVE_PROFILE_REVIEW && targetEnvironment(simulator)
import SwiftUI
import UniformTypeIdentifiers

/// QA-only bilingual labels, excluded from the shipping catalogs and code.
enum NativeReviewQAL10n {
    static func tr(_ key: String) -> String {
        guard AppL10n.effectiveLanguage == "ru" else {return key}
        return russian[key] ?? key
    }
    private static let russian: [String:String] = [
        "Native profiles · Simulator QA": "Нативные профили · тестирование в симуляторе",
        "Simulator QA only. Use synthetic test files. Nothing is saved to the profile library or connected to VPN.": "Только для тестирования в симуляторе. Используйте искусственные тестовые файлы. Профили не сохраняются в библиотеке, VPN не подключается.",
        "Temporary profiles: %d": "Временных профилей: %d",
        "Configuration review": "Проверка конфигурации",
        "Protocol": "Протокол",
        "Choose synthetic configuration text file": "Выбрать тестовый файл конфигурации",
        "Encrypted backup": "Зашифрованная резервная копия",
        "Choose synthetic backup JSON": "Выбрать тестовую копию JSON",
        "Backup password": "Пароль резервной копии",
        "Review backup": "Проверить копию",
        "Prepare encrypted export": "Подготовить зашифрованный экспорт",
        "New password": "Новый пароль",
        "Repeat password": "Повторите пароль",
        "Encrypt": "Зашифровать",
        "Review — counts only": "Предпросмотр — только количество",
        "Add to test memory only": "Добавить только во временную память",
        "Cancel": "Отмена",
        "Discard cancelled file operation": "Сбросить отменённую файловую операцию",
        "Review failed. No new records added.": "Проверка не пройдена. Новые записи не добавлены.",
        "Native profiles · QA": "Нативные профили · тестирование",
        "Close": "Закрыть",
        "Temporary native library": "Временная библиотека нативных профилей",
        "Profile %d": "Профиль %d",
        "Selected for review": "Выбран для проверки",
        "Select for review": "Выбрать для проверки",
        "Connection unavailable — acceptance required": "Подключение недоступно — требуется приёмка",
        "Migration required": "Требуется миграция",
        "Recovery required": "Требуется восстановление",
        "Conflicting profile identifier": "Конфликт идентификатора профиля",
        "Exclusion policy not supported": "Политика исключений не поддерживается",

    ]
}

/// Simulator-only screen; no real store, VPN manager or account.
@MainActor struct NativeProfileReviewLabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var session=NativeProfileReviewSession()
    @State private var kind:NativeCredentialRecord.Kind = .wireGuard
    @State private var summary:NativeRestoreReview.Summary?
    @State private var password=""
    @State private var repeatedPassword=""
    @State private var file:Data?
    @State private var choosing=false
    @State private var lifecycle=NativeReviewFileLifecycle()
    @State private var importReceipt:NativeReviewFileLifecycle.Receipt?
    @State private var exportReceipt:NativeReviewFileLifecycle.Receipt?
    @State private var exporting=false
    @State private var showExporter=false
    @State private var document:RehearsalBackupDocument?
    @State private var exportFilename="APL-Native-QA-Encrypted"
    var legacyIDs:Set<UUID> = []
    var hasExclusions=false
    @State private var library=NativeProfilePresentation.empty
    @State private var failed=false

    init(legacyIDs:Set<UUID> = [],hasExclusions:Bool = false) {self.legacyIDs=legacyIDs;self.hasExclusions=hasExclusions}

    private func tr(_ key: String) -> String { NativeReviewQAL10n.tr(key) }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(tr("Simulator QA only. Use synthetic test files. Nothing is saved to the profile library or connected to VPN."))
                    Text(String(format:tr("Temporary profiles: %d"),Int32(library.rows.count)))
                }
                if !library.rows.isEmpty {
                    Section(tr("Temporary native library")) {
                        ForEach(library.rows) { row in
                            VStack(alignment:.leading,spacing:8) {
                                Text(String(format:tr("Profile %d"),Int32(row.number))+" · "+protocolTitle(row.reference.kind)).font(.headline)
                                if row.selected {Label(tr("Selected for review"),systemImage:"checkmark.circle")}
                                Text(statusTitle(row.state)).font(.footnote).foregroundStyle(.secondary)
                                Button(tr("Select for review")){selectRow(row)}.disabled(!row.canReview || lifecycle.pending != nil)
                            }
                            .accessibilityElement(children:.contain)
                        }
                    }
                }
                Section(tr("Configuration review")) {
                    Picker(tr("Protocol"),selection:$kind) {
                        Text("WireGuard").tag(NativeCredentialRecord.Kind.wireGuard)
                        Text("AmneziaWG 1").tag(NativeCredentialRecord.Kind.amneziaWG1)
                        Text("VLESS Reality").tag(NativeCredentialRecord.Kind.vlessReality)
                    }.onChange(of:kind){_ in resetReview();lifecycle.invalidate();importReceipt=nil}
                    Button(tr("Choose synthetic configuration text file")) { beginImport(.configuration(kind)) }
                }
                Section(tr("Encrypted backup")) {
                    Button(tr("Choose synthetic backup JSON")) { beginImport(.backup) }
                    if file != nil {
                        SecureField(tr("Backup password"),text:$password).textContentType(.password)
                        Button(tr("Review backup"),action:reviewBackup).disabled(password.isEmpty)
                    }
                    Button(tr("Prepare encrypted export")) {resetReview();exporting=true}.disabled(library.rows.isEmpty)
                    if exporting {
                        SecureField(tr("New password"),text:$password).textContentType(.newPassword)
                        SecureField(tr("Repeat password"),text:$repeatedPassword).textContentType(.newPassword)
                        Button(tr("Encrypt"),action:encrypt).disabled(password.count<12 || password != repeatedPassword)
                    }
                }
                if let summary {
                    Section(tr("Review — counts only")) {
                        Text("WireGuard: \(summary.wireGuard)")
                        Text("AmneziaWG 1: \(summary.amneziaWG1)")
                        Text("VLESS Reality: \(summary.vless)")
                        Button(tr("Add to test memory only")) { accept(summary) }
                        Button(tr("Cancel"),role:.cancel){resetReview()}
                    }
                }
                if lifecycle.pending != nil && !choosing && !showExporter {
                    Button(tr("Discard cancelled file operation"),role:.cancel){cancelPanel()}
                }
                if failed { Text(tr("Review failed. No new records added.")).foregroundStyle(.red) }
            }
            .disabled(choosing || showExporter)
            .navigationTitle(tr("Native profiles · QA"))
            .toolbar {ToolbarItem(placement:.cancellationAction){Button(tr("Close")){leave();dismiss()}}}
        }
        .fileImporter(isPresented:$choosing,allowedContentTypes:[.data],allowsMultipleSelection:false, onCompletion:{ [receipt=importReceipt] result in readFile(result,receipt:receipt) })
        .fileExporter(isPresented:$showExporter,document:document,contentType:.json,defaultFilename:exportFilename){ [receipt=exportReceipt] _ in
            guard lifecycle.consume(receipt) == .export else{return}
            document=nil;exportReceipt=nil
        }
        .onAppear { if phase == .active { lifecycle.appear() } }
        .onChange(of:phase){value in
            if value == .background {leave()}
            else if value == .active {lifecycle.appear()}
        }
        .onDisappear {leave()}
    }
    private func protocolTitle(_ kind:NativeCredentialRecord.Kind)->String {
        switch kind {case .wireGuard:return "WireGuard";case .amneziaWG1:return "AmneziaWG 1";case .vlessReality:return "VLESS Reality"}
    }
    private func statusTitle(_ state:NativeProfilePresentation.State)->String {
        switch state {
        case .reviewOnly:return tr("Connection unavailable — acceptance required")
        case .migrationRequired:return tr("Migration required")
        case .recoveryRequired:return tr("Recovery required")
        case .legacyCollision:return tr("Conflicting profile identifier")
        case .unsupportedPolicy:return tr("Exclusion policy not supported")
        }
    }
    private func selectRow(_ row:NativeProfilePresentation.Row){
        guard phase == .active,lifecycle.visible,lifecycle.pending==nil else{return}
        resetReview()
        do{library=try session.selectForReview(row.reference,legacyIDs:legacyIDs,hasExclusions:hasExclusions)}catch{fail()}
    }
    private func resetReview(){session.cancelReview();summary=nil;password="";repeatedPassword="";file=nil;exporting=false;failed=false}
    private func fail(){resetReview();failed=true}
    private func cancelPanel(){lifecycle.invalidate();importReceipt=nil;exportReceipt=nil;document=nil;resetReview()}
    private func leave(){lifecycle.leave();resetReview();session.clear();importReceipt=nil;exportReceipt=nil;choosing=false;showExporter=false;document=nil;library = .empty}
    private func beginImport(_ action:NativeReviewFileLifecycle.Action){
        guard phase == .active,lifecycle.pending==nil else{return}
        resetReview();guard let receipt=lifecycle.begin(action) else{return};importReceipt=receipt;choosing=true
    }
    private func readFile(_ result:Result<[URL],Error>,receipt:NativeReviewFileLifecycle.Receipt?){
        guard let action=lifecycle.consume(receipt) else{return}
        importReceipt=nil

        do {
            guard let url=try result.get().first else{return}
            guard url.isFileURL else{throw ProfileBackupError.invalidFile}
            let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
            switch action {
            case .backup: file=try ProfileBackupCodec.readEncryptedFile(at:url)
            case .configuration(let reviewedKind):
                let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
                var bytes=Data()
                while bytes.count<=NativeCredentialRecord.maxBytes {
                    let part=try handle.read(upToCount:NativeCredentialRecord.maxBytes+1-bytes.count) ?? Data()
                    if part.isEmpty{break};bytes.append(part)
                }
                guard bytes.count<=NativeCredentialRecord.maxBytes,let raw=String(data:bytes,encoding:.utf8) else {throw ProfileBackupError.invalidFile}
                summary=try session.previewSource(raw,kind:reviewedKind)
            case .export:throw ProfileBackupError.invalidFile
            }
        } catch {fail()}
    }
    private func reviewBackup(){guard phase == .active,lifecycle.visible,lifecycle.pending==nil,let file else{return};let p=password;resetReview();do{summary=try session.previewBackup(file,password:p)}catch{fail()}}
    private func accept(_ value:NativeRestoreReview.Summary){guard phase == .active,lifecycle.visible,lifecycle.pending==nil else{return};do{_=try session.addToRehearsal(value);library=try session.presentation(legacyIDs:legacyIDs,hasExclusions:hasExclusions);resetReview()}catch{fail()}}
    private func encrypt(){guard phase == .active,lifecycle.visible,lifecycle.pending==nil,password==repeatedPassword else{fail();return};let p=password;resetReview();do{let bytes=try session.encryptedBackup(password:p);guard let receipt=lifecycle.begin(.export) else{throw ProfileBackupError.invalidFile};exportReceipt=receipt;exportFilename="APL-Native-QA-Encrypted-"+receipt.id.uuidString.lowercased();document=RehearsalBackupDocument(bytes:bytes);showExporter=true}catch{fail()}}
}
private struct RehearsalBackupDocument:FileDocument {
    static var readableContentTypes:[UTType]{[.json]}
    let bytes:Data
    init(bytes:Data){self.bytes=bytes}
    init(configuration:ReadConfiguration)throws{guard let b=configuration.file.regularFileContents,b.count<=ProfileBackupCodec.maxFileBytes else{throw ProfileBackupError.invalidFile};bytes=b}
    func fileWrapper(configuration:WriteConfiguration)throws->FileWrapper{FileWrapper(regularFileWithContents:bytes)}
}
#endif
