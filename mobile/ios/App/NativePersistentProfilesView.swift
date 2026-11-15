#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PERSISTENT_LIBRARY && !targetEnvironment(simulator)
import SwiftUI
import UniformTypeIdentifiers

/// Explicit device Debug candidate, never a connection or legacy selection UI.
@MainActor struct NativePersistentProfilesView:View {
    @ObservedObject var model:AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var session:NativePersistentProfileSession?
    @State private var library:NativePersistentProfileSession.State?
    @State private var receipt:NativePersistentProfileSession.Receipt?
    @State private var summary:NativeRestoreReview.Summary?
    @State private var kind:NativeCredentialRecord.Kind = .wireGuard
    @State private var lifecycle=NativeReviewFileLifecycle()
    @State private var fileReceipt:NativeReviewFileLifecycle.Receipt?
    @State private var choosing=false
    @State private var backupBytes:Data?
    @State private var password=""
    @State private var repeatedPassword=""
    @State private var document:NativePersistentBackupDocument?
    @State private var exporting=false
    @State private var exportReceipt:NativeReviewFileLifecycle.Receipt?
    @State private var exportName="APL-Native-Encrypted"
    @State private var busy=false
    @State private var failed=false
    @State private var generation=UUID()
    static var title:String {label("Native profiles · storage QA","Нативные профили · проверка хранилища")}
    private static func label(_ en:String,_ ru:String)->String {AppL10n.effectiveLanguage=="ru" ? ru:en}
    private func tr(_ en:String,_ ru:String)->String {Self.label(en,ru)}
    var body:some View {
        NavigationView {
            Form {
                Section {
                    Text(tr("Device validation only. Use test profiles. Connection is disabled.","Только проверка на устройстве. Используйте тестовые профили. Подключение отключено."))
                    if failed {Text(tr("Operation failed. Reload to check saved state and recovery.","Операция не завершена. Обновите список и проверьте восстановление.")).foregroundStyle(.red)}
                    Button(tr("Reload","Обновить"),action:reload)
                }
                if let library {librarySections(library)}
                if let receipt {
                    Section(tr("Confirm operation","Подтверждение операции")) {
                        Text(actionTitle(receipt.action));Text(tr("Affected records: ","Затронуто записей: ")+String(receipt.affected))
                        if let row=targetRow(receipt.action) {Text("\(row.number). \(row.reference.kind.rawValue)")}
                        if receipt.action == .exportBackup {
                            SecureField(tr("New password","Новый пароль"),text:$password).textContentType(.newPassword)
                            SecureField(tr("Repeat password","Повторите пароль"),text:$repeatedPassword).textContentType(.newPassword)
                            Button(tr("Encrypt and export","Зашифровать и экспортировать")){exportBackup(receipt)}.disabled(password.count<12 || password != repeatedPassword)
                        } else {Button(tr("Confirm","Подтвердить")){apply(receipt:receipt,summary:nil)}}
                        Button(tr("Cancel","Отмена"),role:.cancel){cancelReview()}
                    }
                }
                if let summary {
                    Section(tr("Review import","Предпросмотр импорта")) {
                        Text("WireGuard: \(summary.wireGuard) · AWG: \(summary.amneziaWG1) · VLESS: \(summary.vless)")
                        Text(tr("Add without changing the selected profile.","Добавить без изменения выбранного профиля."))
                        Button(tr("Save reviewed profiles","Сохранить проверенные профили")){apply(receipt:nil,summary:summary)}
                        Button(tr("Cancel","Отмена"),role:.cancel){cancelReview()}
                    }
                }
                if lifecycle.pending != nil && !choosing && !exporting {Button(tr("Discard file operation","Отменить файловую операцию")){lifecycle.invalidate();fileReceipt=nil;exportReceipt=nil;document=nil;cancelReview()}}
            }.disabled(busy || choosing || exporting).navigationTitle(Self.title)
            .toolbar {ToolbarItem(placement:.cancellationAction){Button(tr("Close","Закрыть")){leave();dismiss()}}}
        }
        .fileImporter(isPresented:$choosing,allowedContentTypes:[.data],allowsMultipleSelection:false,onCompletion:{[token=fileReceipt] result in receive(result,token:token)})
        .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:exportName){[token=exportReceipt] _ in
            guard lifecycle.consume(token) == .export else{return}
            document=nil;exportReceipt=nil
        }
        .onAppear {if phase == .active {enter()}}
        .onChange(of:phase){value in if value == .active {enter()} else if value == .background {leave()}}
        .onDisappear {leave()}
    }
    @ViewBuilder private func librarySections(_ library:NativePersistentProfileSession.State)->some View {
        if library.migrationRequired || library.recoveryRequired || library.retiredCount>0 {
            Section(tr("Storage maintenance","Обслуживание хранилища")) {
                if library.migrationRequired {Button(tr("Review migration","Проверить миграцию")){prepare(.migrate)}}
                else if library.recoveryRequired {Button(tr("Review interrupted operation","Проверить прерванную операцию")){prepare(.recover)}}
                else if library.retiredCount>0 {Button(tr("Review retired revisions","Проверить удалённые ревизии")){prepare(.purgeRetired)}}
            }
        }
        if !library.policyAllowsSelection {Text(policyTitle(library.policy))}
        if library.selectionNeedsReview {Text(tr("Select again after migration.","После миграции выберите профиль повторно."))}
        Section(tr("Native library","Библиотека нативных профилей")) {
            if library.library.rows.isEmpty {Text(tr("No native profiles","Нет нативных профилей"))}
            ForEach(library.library.rows) {row in
                VStack(alignment:.leading,spacing:8) {
                    Text("\(row.number). \(row.reference.kind.rawValue)").font(.headline)
                    if row.selected {Text(tr("Selected for review","Выбран для проверки"))}
                    Text(status(row.state)).font(.footnote).foregroundStyle(.secondary)
                    Button(tr("Review selection","Проверить выбор")){prepare(.select(row.reference))}.disabled(!row.canReview)
                    Button(tr("Review removal","Проверить удаление"),role:.destructive){prepare(.remove(row.reference))}.disabled(library.migrationRequired || library.recoveryRequired)
                }
            }
        }
        if !library.migrationRequired && !library.recoveryRequired {
            Section(tr("Import test profile","Импорт тестового профиля")) {
                Picker(tr("Protocol","Протокол"),selection:$kind) {
                    Text("WireGuard").tag(NativeCredentialRecord.Kind.wireGuard)
                    Text("AmneziaWG 1").tag(NativeCredentialRecord.Kind.amneziaWG1)
                    Text("VLESS Reality").tag(NativeCredentialRecord.Kind.vlessReality)
                }.onChange(of:kind){_ in cancelReview();lifecycle.invalidate();fileReceipt=nil}
                Button(tr("Choose configuration file","Выбрать файл конфигурации")){choose(.configuration(kind))}
            }
            Section(tr("Encrypted native backup","Зашифрованная копия нативных профилей")) {
                Button(tr("Choose encrypted backup","Выбрать зашифрованную копию")){choose(.backup)}
                if backupBytes != nil {
                    SecureField(tr("Backup password","Пароль резервной копии"),text:$password).textContentType(.password)
                    Button(tr("Review backup","Проверить копию")){reviewBackup()}.disabled(password.isEmpty)
                }
                Button(tr("Review encrypted export","Проверить зашифрованный экспорт")){prepare(.exportBackup)}.disabled(library.library.rows.isEmpty)
            }
        }
    }
    private func policyTitle(_ policy:NativeRoutingAdmission)->String {
        switch policy {
        case .tunnelOnly:return tr("Tunnel only","Только туннель")
        case .siteExclusions:return tr("Site exclusions are not supported by native candidates.","Исключения сайтов не поддерживаются нативными кандидатами.")
        case .dependencyPolicy:return tr("Stored dependency approvals require routing acceptance.","Сохранённые разрешения связанных доменов требуют приёмки маршрутизации.")
        case .normallyOff:return tr("Normally-off routing is not supported.","Режим «обычно выключен» не поддерживается.")
        case .malformed:return tr("Routing settings are invalid. No native selection.","Настройки маршрутизации повреждены. Выбор заблокирован.")
        }
    }
    private func status(_ s:NativeProfilePresentation.State)->String {
        switch s {
        case .reviewOnly:return tr("Connection unavailable","Подключение недоступно")
        case .migrationRequired:return tr("Migration required","Требуется миграция")
        case .recoveryRequired:return tr("Recovery required","Требуется восстановление")
        case .legacyCollision:return tr("Profile identifier conflict","Конфликт идентификатора профиля")
        case .unsupportedPolicy:return tr("Unsupported policy","Политика не поддерживается")
        }
    }
    private func targetRow(_ action:NativePersistentProfileSession.Action)->NativeProfilePresentation.Row? {
        switch action {
        case .select(let ref),.remove(let ref):return library?.library.rows.first{$0.reference==ref}
        default:return nil
        }
    }
    private func actionTitle(_ a:NativePersistentProfileSession.Action)->String {
        switch a {
        case .exportBackup:return tr("Export current native profiles only, encrypted with your password.","Экспортировать только текущие нативные профили в зашифрованном виде.")
        case .migrate:return tr("Migrate metadata; require explicit reselection.","Обновить метаданные; потребуется повторный выбор.")
        case .recover:return tr("Roll back only the recorded incomplete operation.","Отменить только записанную незавершённую операцию.")
        case .purgeRetired:return tr("Permanently delete only retired credentials.","Окончательно удалить только выведенные из обращения ключи.")
        case .select:return tr("Select for review, not connection.","Выбрать для проверки, не для подключения.")
        case .remove:return tr("Remove from library; credentials remain until separate cleanup.","Удалить из библиотеки; ключи останутся до отдельной очистки.")
        }
    }
    private func cancelReview(){session?.cancel();receipt=nil;summary=nil;backupBytes=nil;password="";repeatedPassword=""}
    private func leave(){generation=UUID();lifecycle.leave();cancelReview();session=nil;library=nil;fileReceipt=nil;exportReceipt=nil;document=nil;exporting=false;choosing=false;busy=false}
    private func enter(){guard session==nil else{return};lifecycle.appear();session=model.makePersistentNativeLibrary();reload()}
    private func reload(){cancelReview();failed=false;do{library=try session?.state()}catch{library=nil;failed=true}}
    private func prepare(_ action:NativePersistentProfileSession.Action){guard !busy,lifecycle.visible,lifecycle.pending==nil,let session else{return};cancelReview();do{receipt=try session.prepare(action)}catch{failed=true}}
    private func choose(_ action:NativeReviewFileLifecycle.Action){guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil else{return};cancelReview();fileReceipt=lifecycle.begin(action);choosing=fileReceipt != nil}
    private func receive(_ result:Result<[URL],Error>,token:NativeReviewFileLifecycle.Receipt?){
        guard let action=lifecycle.consume(token),let session else{return};fileReceipt=nil
        do {
            guard let url=try result.get().first,url.isFileURL else{return}
            let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
            if action == .backup {backupBytes=try ProfileBackupCodec.readEncryptedFile(at:url);return}
            guard case .configuration(let kind)=action else{throw ProfileBackupError.invalidFile}
            let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()};var data=Data()
            while data.count<=NativeCredentialRecord.maxBytes {
                let part=try handle.read(upToCount:NativeCredentialRecord.maxBytes+1-data.count) ?? Data()
                if part.isEmpty{break};data.append(part)
            }
            guard data.count<=NativeCredentialRecord.maxBytes,let raw=String(data:data,encoding:.utf8) else{throw ProfileBackupError.invalidFile}
            summary=try session.previewSource(raw,kind:kind)
        }catch{cancelReview();failed=true}
    }
    private func reviewBackup(){
        guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil,let bytes=backupBytes,let session else{return}
        let secret=password;cancelReview()
        do{summary=try session.previewBackup(bytes,password:secret)}catch{failed=true}
    }
    private func exportBackup(_ receipt:NativePersistentProfileSession.Receipt){
        guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil,password==repeatedPassword,let session else{return}
        busy=true;let token=generation,secret=password;password="";repeatedPassword=""
        Task { @MainActor in
            do {
                var encrypted:Data?
                try await model.vpn.withNativeLibraryWrite { inactive in
                    guard generation==token,lifecycle.visible,phase == .active else{throw NativePersistentProfileSession.Failure.stale}
                    encrypted=try session.confirmExport(receipt,password:secret,vpnInactive:inactive)
                }
                if generation==token {
                    guard let encrypted,let panel=lifecycle.begin(.export),phase == .active else{throw NativePersistentProfileSession.Failure.stale}
                    cancelReview();exportReceipt=panel;document=NativePersistentBackupDocument(bytes:encrypted)
                    exportName="APL-Native-Encrypted-"+panel.id.uuidString.lowercased();exporting=true
                }
            }catch{if generation==token {cancelReview();failed=true}}
            if generation==token {busy=false}
        }
    }
    private func apply(receipt:NativePersistentProfileSession.Receipt?,summary:NativeRestoreReview.Summary?){
        guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil,let session else{return};busy=true;let token=generation
        Task { @MainActor in
            do {
                try await model.vpn.withNativeLibraryWrite { inactive in
                    guard generation==token,lifecycle.visible,phase == .active else{throw NativePersistentProfileSession.Failure.stale}
                    if let receipt {try session.confirm(receipt,vpnInactive:inactive)}
                    else if let summary {try session.confirmImport(summary,vpnInactive:inactive)}
                    else{throw NativePersistentProfileSession.Failure.stale}
                }
                if generation==token {reload()}
            } catch {if generation==token {reload();failed=true}}
            if generation==token {busy=false}
        }
    }
}
private struct NativePersistentBackupDocument:FileDocument {
    static var readableContentTypes:[UTType]{[.json]}
    let bytes:Data
    init(bytes:Data){self.bytes=bytes}
    init(configuration:ReadConfiguration)throws {guard let b=configuration.file.regularFileContents,b.count<=ProfileBackupCodec.maxFileBytes else{throw ProfileBackupError.invalidFile};bytes=b}
    func fileWrapper(configuration:WriteConfiguration)throws->FileWrapper {FileWrapper(regularFileWithContents:bytes)}
}
#endif
