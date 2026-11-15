#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PERSISTENT_LIBRARY && !targetEnvironment(simulator)
import SwiftUI
import UniformTypeIdentifiers
import UIKit
#if APL_NATIVE_IP_ROUTE_REVIEW
import NetworkExtension
#endif

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
    @State private var authenticationFailed=false
    @State private var exportSaved=false
    @State private var generation=UUID()
    @State private var profileSearch=""
    @State private var renameTarget:NativeCredentialRecord.Reference?
    @State private var nameDraft=""
    @State private var showRename=false
    @State private var replacementTarget:NativeCredentialRecord.Reference?
    #if APL_NATIVE_IP_ROUTE_REVIEW
    @State private var ipRuleText=""
    @State private var ipOptIn=false
    @State private var ipPreview:[String]?
    #endif
    static var title:String {label("Native profiles · storage QA","Нативные профили · проверка хранилища")}
    private static func label(_ en:String,_ ru:String)->String {AppL10n.effectiveLanguage=="ru" ? ru:en}
    private func tr(_ en:String,_ ru:String)->String {Self.label(en,ru)}
    var body:some View {
        NavigationView {
            Form {
                Section {
                    Text(tr("Device validation only. Use test profiles. Connection is disabled.","Только проверка на устройстве. Используйте тестовые профили. Подключение отключено."))
                    if exportSaved {Text(tr("Encrypted backup saved","Зашифрованная копия сохранена"))}
                    if authenticationFailed {Text(tr("Wrong password or damaged backup. Try again.","Неверный пароль или повреждённая копия. Повторите ввод.")).foregroundStyle(.red)}
                    if failed {Text(tr("Operation failed. Reload to check saved state and recovery.","Операция не завершена. Обновите список и проверьте восстановление.")).foregroundStyle(.red)}
                    Button(tr("Reload","Обновить"),action:reload)
                }
                if let library {librarySections(library)}
                if let receipt {
                    Section(tr("Confirm operation","Подтверждение операции")) {
                        Text(actionTitle(receipt.action));Text(tr("Affected records: ","Затронуто записей: ")+String(receipt.affected))
                        if let row=targetRow(receipt.action) {Text(rowTitle(row))}
                        if case .rename(_,let name)=receipt.action {Text(name.isEmpty ? tr("Default name","Имя по умолчанию"):name)}
                        if receipt.action == .exportBackup {
                            SecureField(tr("New password","Новый пароль"),text:$password).textContentType(.newPassword)
                            SecureField(tr("Repeat password","Повторите пароль"),text:$repeatedPassword).textContentType(.newPassword)
                            Button(tr("Encrypt and export","Зашифровать и экспортировать")){exportBackup(receipt)}.disabled(password.count<12 || password != repeatedPassword)
                        } else {Button(tr("Confirm","Подтвердить")){apply(receipt:receipt,summary:nil)}}
                        Button(tr("Cancel","Отмена"),role:.cancel){cancelReview()}
                    }
                }
                if let target=replacementTarget,let row=library?.library.rows.first(where:{$0.reference==target}) {
                    Section(tr("Replace configuration","Замена конфигурации")) {
                        Text(rowTitle(row)).font(.headline)
                        Text(tr("Import a new configuration of the same protocol. The current configuration is not displayed.","Загрузите новую конфигурацию того же протокола. Текущие ключи не отображаются."))
                        Button(tr("Choose replacement file","Выбрать новый файл")){choose(.replacement(target))}
                        Button(tr("Use clipboard","Вставить из буфера")){previewReplacementClipboard(target)}
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
        .fileImporter(isPresented:$choosing,allowedContentTypes:[.data],allowsMultipleSelection:fileReceipt?.action == .automaticConfigurations,onCompletion:{[token=fileReceipt] result in receive(result,token:token)})
        .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:exportName){[token=exportReceipt] result in
            guard lifecycle.consume(token) == .export else{return}
            document=nil;exportReceipt=nil
            switch result {case .success:exportSaved=true;case .failure:failed=true}
        }
        .alert(tr("Profile name","Имя профиля"),isPresented:$showRename) {
            TextField(tr("Name (optional)","Имя (необязательно)"),text:$nameDraft)
            Button(tr("Review","Проверить")){reviewRename()}
            Button(tr("Cancel","Отмена"),role:.cancel){renameTarget=nil;nameDraft=""}
        } message:{Text(tr("A label only. Leave empty to use the default name.","Только название. Оставьте пустым для имени по умолчанию."))}
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
        #if APL_NATIVE_DOMAIN_POLICY_REVIEW
        if !library.policyAllowsSelection {
            Section(tr("Existing routing rules · read only","Существующие правила маршрутизации · только просмотр")) {
                Text(tr("Native connections remain disabled. These are stored rules, not applied routes.","Нативные подключения остаются недоступными. Это сохранённые правила, а не применённые маршруты."))
                if let review=try? model.nativeDomainPolicyReview() {
                    if review.admission != library.policy {Text(tr("Policy changed; reload.","Политика изменилась; обновите список."))}
                    else {
                        if review.normallyOff {Text(tr("Normally-off policy","Режим «обычно выключен»"))}
                        ForEach(review.rows) {row in VStack(alignment:.leading,spacing:4) {
                            Text(row.host).font(.system(.footnote,design:.monospaced))
                            if let parent=row.parent {Text(parent).font(.caption).foregroundStyle(.secondary)}
                            Text(domainSource(row.source)+" · "+domainStatus(row.status)).font(.caption)
                        }}
                    }
                } else {Text(tr("Policy cannot be reviewed safely.","Не удалось безопасно прочитать политику."))}
            }
        }
        #endif
        if library.selectionNeedsReview {Text(tr("Select again after migration.","После миграции выберите профиль повторно."))}
        Section(tr("Native library","Библиотека нативных профилей")) {
            if library.library.rows.isEmpty {Text(tr("No native profiles","Нет нативных профилей"))}
            if !library.library.rows.isEmpty {
                TextField(tr("Find profile","Найти профиль"),text:$profileSearch).autocorrectionDisabled()
            }
            let rows=library.library.rows.filter {row in
                let q=profileSearch.trimmingCharacters(in:.whitespacesAndNewlines)
                return q.isEmpty || rowTitle(row).localizedCaseInsensitiveContains(q) || protocolTitle(row.reference.kind).localizedCaseInsensitiveContains(q) || row.shortID.localizedCaseInsensitiveContains(q)
            }
            if rows.isEmpty && !library.library.rows.isEmpty {Text(tr("No matching profiles","Профили не найдены"))}
            ForEach(rows) {row in
                VStack(alignment:.leading,spacing:8) {
                    Text(rowTitle(row)).font(.headline)
                    Text(protocolTitle(row.reference.kind)+" · "+row.shortID).font(.caption).foregroundStyle(.secondary)
                    if row.selected {Text(tr("Selected for review","Выбран для проверки"))}
                    Text(status(row.state)).font(.footnote).foregroundStyle(.secondary)
                    Button(tr("Review selection","Проверить выбор")){prepare(.select(row.reference))}.buttonStyle(.borderless).disabled(!row.canReview)
                    Button(tr("Rename","Переименовать")){beginRename(row)}.buttonStyle(.borderless).disabled(library.migrationRequired || library.recoveryRequired || row.state == .legacyCollision)
                    Button(tr("Replace configuration","Заменить конфигурацию")){beginReplacement(row)}.buttonStyle(.borderless).disabled(library.migrationRequired || library.recoveryRequired || row.state == .legacyCollision || library.retiredCount>=64)
                    Button(tr("Review removal","Проверить удаление"),role:.destructive){prepare(.remove(row.reference))}.buttonStyle(.borderless).disabled(library.migrationRequired || library.recoveryRequired)
                }
            }
        }
        #if APL_NATIVE_IP_ROUTE_REVIEW
        if let row=library.library.rows.first(where:{$0.selected && $0.canReview && $0.reference.kind != .vlessReality}),library.policyAllowsSelection,!library.selectionNeedsReview,!library.migrationRequired,!library.recoveryRequired {
            Section(tr("Explicit IP route preview","Предпросмотр IP-маршрутов")) {
                Text(tr("One literal IP or network per line. Applies to every destination in that network, not a domain. Preview only; no routes are applied.","Один IP или CIDR в строке. Правило относится ко всем адресам сети, а не к домену. Только предпросмотр; маршруты не применяются."))
                TextEditor(text:$ipRuleText).frame(minHeight:76).textInputAutocapitalization(.never).disableAutocorrection(true).onChange(of:ipRuleText){_ in ipPreview=nil;ipOptIn=false}
                Toggle(tr("I understand the IP-wide scope","Понимаю действие правила на всю IP-сеть"),isOn:$ipOptIn).onChange(of:ipOptIn){_ in ipPreview=nil}
                Button(tr("Preview excluded routes","Проверить исключаемые маршруты")){previewIPRoutes(row.reference)}.disabled(!ipOptIn || ipRuleText.isEmpty || ipRuleText.utf8.count>4096)
                if let ipPreview {ForEach(ipPreview,id:\.self){Text($0).font(.system(.footnote,design:.monospaced))};Text(tr("Settings object verified, not applied.","Объект настроек проверен, не применён.")).font(.footnote)}
            }
        }
        #endif
        if !library.migrationRequired && !library.recoveryRequired {
            Section(tr("Import test profile","Импорт тестового профиля")) {
                Button(tr("Choose files · detect protocol","Выбрать файлы · автоопределение")){choose(.automaticConfigurations)}.accessibilityIdentifier("nativeImport.autoFiles")
                Button(tr("Import from clipboard","Импорт из буфера")){previewClipboard()}.accessibilityIdentifier("nativeImport.clipboard")
                Text(tr("One WG/AWG configuration per file, or VLESS links one per line. Unsupported entries reject the entire batch.","Одна конфигурация WG/AWG на файл или ссылки VLESS по одной в строке. Неподдерживаемая запись отменяет всю проверку пакета.")).font(.footnote)
                Picker(tr("Protocol","Протокол"),selection:$kind) {
                    Text("WireGuard").tag(NativeCredentialRecord.Kind.wireGuard)
                    Text("AmneziaWG 1").tag(NativeCredentialRecord.Kind.amneziaWG1)
                    Text("VLESS Reality").tag(NativeCredentialRecord.Kind.vlessReality)
                }.onChange(of:kind){_ in cancelReview();lifecycle.invalidate();fileReceipt=nil}
                Button(tr("Choose single file with selected protocol","Выбрать один файл указанного протокола")){choose(.configuration(kind))}
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
    #if APL_NATIVE_DOMAIN_POLICY_REVIEW
    private func domainSource(_ s:NativeDomainPolicyReview.Source)->String {
        switch s {case .manual:return tr("Manual","Вручную");case .derivedAlias:return tr("Existing alias / curated dependency","Существующий алиас / известная связь");case .legacyOnly:return tr("Legacy-only entry","Только старые настройки");case .dependency:return tr("Related domain","Связанный домен")}
    }
    private func domainStatus(_ s:NativeDomainPolicyReview.Status)->String {
        switch s {case .configured:return tr("Configured","Задан");case .approved:return tr("Prior approval","Ранее одобрен");case .pending:return tr("Pending","Ожидает");case .rejected:return tr("Rejected","Отклонён");case .expired:return tr("Outdated","Устарел");case .orphaned:return tr("Parent absent","Нет родительского сайта");case .suppressed:return tr("Removed","Удалён");case .ambiguous:return tr("Ambiguous","Неоднозначен");case .invalid:return tr("Invalid","Некорректен")}
    }
    #endif
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
    private func protocolTitle(_ kind:NativeCredentialRecord.Kind)->String {
        switch kind {case .wireGuard:return "WireGuard";case .amneziaWG1:return "AmneziaWG 1";case .vlessReality:return "VLESS Reality"}
    }
    private func rowTitle(_ row:NativeProfilePresentation.Row)->String {row.displayName ?? protocolTitle(row.reference.kind)+" · "+row.shortID}
    private func beginRename(_ row:NativeProfilePresentation.Row){
        guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil else{return}
        cancelReview();renameTarget=row.reference;nameDraft=row.displayName ?? "";showRename=true
    }
    private func reviewRename(){
        guard phase == .active,let target=renameTarget else{return}
        let name=nameDraft;renameTarget=nil;nameDraft=""
        do{let label=try NativeCredentialRecord.normalizedDisplayName(name);prepare(.rename(target,label ?? ""))}catch{failed=true}
    }
    private func targetRow(_ action:NativePersistentProfileSession.Action)->NativeProfilePresentation.Row? {
        switch action {
        case .select(let ref),.remove(let ref),.rename(let ref,_),.replace(let ref):return library?.library.rows.first{$0.reference==ref}
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
        case .rename:return tr("Rename profile without changing credentials.","Переименовать профиль без изменения ключей.")
        case .replace:return tr("Save new validated configuration, keep the name and ID. If selected, select again before connection. Old credentials remain retired until cleanup.","Сохранить новую проверенную конфигурацию, сохранив имя и ID. Если профиль выбран, потребуется повторный выбор. Старые ключи останутся выведенными из обращения до очистки.")
        case .remove:return tr("Remove from library; credentials remain until separate cleanup.","Удалить из библиотеки; ключи останутся до отдельной очистки.")
        }
    }
    private func cancelReview(){replacementTarget=nil;renameTarget=nil;nameDraft="";showRename=false;authenticationFailed=false;exportSaved=false;session?.cancel();receipt=nil;summary=nil;backupBytes=nil;password="";repeatedPassword=""
        #if APL_NATIVE_IP_ROUTE_REVIEW
        ipPreview=nil;ipOptIn=false;ipRuleText=""
        #endif
    }
    private func leave(){generation=UUID();lifecycle.leave();cancelReview();session=nil;library=nil;fileReceipt=nil;exportReceipt=nil;document=nil;exporting=false;choosing=false;busy=false}
    private func enter(){guard session==nil else{return};lifecycle.appear();session=model.makePersistentNativeLibrary();reload()}
    private func reload(){cancelReview();failed=false;do{library=try session?.state()}catch{library=nil;failed=true}}
    private func prepare(_ action:NativePersistentProfileSession.Action){guard !busy,lifecycle.visible,lifecycle.pending==nil,let session else{return};cancelReview();do{receipt=try session.prepare(action)}catch{failed=true}}
    private func choose(_ action:NativeReviewFileLifecycle.Action){guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil else{return};cancelReview();fileReceipt=lifecycle.begin(action);choosing=fileReceipt != nil}
    private func receive(_ result:Result<[URL],Error>,token:NativeReviewFileLifecycle.Receipt?){
        guard let action=lifecycle.consume(token),let session else{return};fileReceipt=nil
        do {
            let urls=try result.get()
            if action == .automaticConfigurations {
                summary=try session.previewAutomatic(NativeAutomaticImport.readSources(urls));return
            }
            guard urls.count==1,let url=urls.first,url.isFileURL else{throw ProfileBackupError.invalidFile}
            if action == .backup {
                let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
                backupBytes=try ProfileBackupCodec.readEncryptedFile(at:url);return
            }
            if case .replacement(let target)=action {
                let raw=try NativeAutomaticImport.readSource(url,limit:NativeCredentialRecord.maxBytes)
                receipt=try session.previewReplacement(raw,for:target);return
            }
            guard case .configuration(let kind)=action else{throw ProfileBackupError.invalidFile}
            let raw=try NativeAutomaticImport.readSource(url,limit:NativeCredentialRecord.maxBytes)
            summary=try session.previewSource(raw,kind:kind)
        }catch{cancelReview();failed=true}
    }
    private func beginReplacement(_ row:NativeProfilePresentation.Row){
        guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil else{return}
        cancelReview();failed=false;replacementTarget=row.reference
    }
    private func previewReplacementClipboard(_ target:NativeCredentialRecord.Reference){
        guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil,replacementTarget==target,let session else{return}
        cancelReview();failed=false
        do {guard let source=UIPasteboard.general.string else{throw NativeAutomaticImport.Failure.empty};receipt=try session.previewReplacement(source,for:target)}catch{failed=true}
    }
    private func previewClipboard(){
        guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil,let session else{return}
        cancelReview();failed=false
        do {
            guard let text=UIPasteboard.general.string else{throw NativeAutomaticImport.Failure.empty}
            summary=try session.previewAutomatic([text])
        }catch{cancelReview();failed=true}
    }
    private func reviewBackup(){
        guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil,let bytes=backupBytes,let session else{return}
        let secret=password;cancelReview();failed=false
        do{summary=try session.previewBackup(bytes,password:secret)}catch ProfileBackupError.authenticationFailed {backupBytes=bytes;authenticationFailed=true}catch{failed=true}
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
    #if APL_NATIVE_IP_ROUTE_REVIEW
    private func previewIPRoutes(_ ref:NativeCredentialRecord.Reference){
        guard phase == .active,!busy,lifecycle.visible,lifecycle.pending==nil,ipOptIn,ipRuleText.utf8.count<=4096,let session else{return}
        let rules=ipRuleText.split(separator:"\n").map(String.init),token=generation
        receipt=nil;summary=nil;backupBytes=nil;password="";repeatedPassword="";ipPreview=nil;failed=false;busy=true
        Task { @MainActor in
            do {
                var result:[String]?
                try await model.vpn.withNativeLibraryWrite {inactive in
                    guard generation==token,lifecycle.visible,phase == .active,ipOptIn else{throw NativePersistentProfileSession.Failure.stale}
                    let plan=try session.previewIPRoutes(for:ref,explicitRules:rules,explicitIPOptIn:true,vpnInactive:inactive)
                    let object=NativeTunnelNetworkSettings.makeExplicitIPReview(plan)
                    guard let v4=object.ipv4Settings?.excludedRoutes,let v6=object.ipv6Settings?.excludedRoutes,
                          v4.map({$0.destinationAddress+"/"+$0.destinationSubnetMask})==plan.ipv4Exclusions.map({$0.address+"/"+($0.ipv4Mask ?? "INVALID")}),
                          v6.map({$0.destinationAddress+"/"+$0.destinationNetworkPrefixLength.stringValue})==plan.ipv6Exclusions.map(\.description) else{throw NativePersistentProfileSession.Failure.unavailable}
                    result=plan.exclusions.map(\.description)
                }
                if generation==token,phase == .active {ipPreview=result}
            }catch{if generation==token{ipPreview=nil;failed=true}}
            if generation==token{busy=false}
        }
    }
    #endif
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
