import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ProxyImportView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var source = ""
    @State private var subscriptionURL = ""
    @State private var subscriptionTitle = ""
    @State private var savedSubscriptions: [SavedProxySubscription] = []
    @State private var isFetchingSubscription = false
    @State private var subscriptionTask: Task<Void, Never>?
    @State private var refreshGeneration=UUID()
    @State private var visible=false
    @State private var automaticPreview:SavedProxySubscription?
    @State private var activeSavedSource:SavedProxySubscription?
    @State private var defaultType: ProxyType = .http
    @State private var parsedType: ProxyType = .http
    @State private var candidates: [ImportedProxy] = []
    @State private var parsedSource = ""
    @State private var importError: String?
    @State private var chooseFile = false
    @State private var scanQR = false
    @State private var cameraReady = false
    @State private var cameraPermissionDenied = false
    @FocusState private var editorFocused: Bool
    var initialSource: String = ""
    private var preview: [ImportedProxy] {
        if automaticPreview != nil {return candidates}
        return parsedSource == source && parsedType == defaultType ? candidates : []
    }
    private var pending: [ImportedProxy] {
        ProxyImport.withoutDuplicates(preview, existing: model.profiles)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(ProxyImportUX.text("Ссылка или список прокси")) {
                    Picker(ProxyImportUX.text("Тип прокси по умолчанию"), selection: $defaultType) {
                        Text("HTTP").tag(ProxyType.http)
                        Text("HTTPS").tag(ProxyType.https)
                        Text("SOCKS5").tag(ProxyType.socks5)
                    }
                    .onChange(of: defaultType) { _ in
                        if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parse() }
                    }
                    TextEditor(text: $source).frame(minHeight: 110)
                        .focused($editorFocused)
                        .accessibilityLabel(ProxyImportUX.text("Текст ссылок на прокси"))
                        .onChange(of: source) { _ in if parsedSource != source { importError = nil } }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(ProxyImportUX.text("Вставить из буфера")) {
                        guard let pasted = UIPasteboard.general.string,
                              !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            importError = ProxyImportUX.text("Буфер обмена не содержит ссылки на прокси")
                            return
                        }
                        source = pasted
                        parse()
                    }
                    Button(ProxyImportUX.text("Выбрать файл")) { chooseFile = true }
                    Button(ProxyImportUX.text("Сканировать QR-код")) {
                        editorFocused = false
                        cameraReady = false
                        cameraPermissionDenied = false
                        scanQR = true
                    }
                    Button(ProxyImportUX.text("Проверить")) {
                        editorFocused = false
                        parse()
                    }
                    Text(ProxyImportUX.text("Вставьте ссылки, IP:порт:логин:пароль или TXT/CSV/XML до 200 прокси. Тип выше применяется только к строкам без протокола."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .disabled(automaticPreview != nil)
                Section(ProxyImportUX.text("Список от поставщика")) {
                    TextField(ProxyImportUX.text("HTTPS-ссылка на подписку"), text: $subscriptionURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("profiles.subscriptionURL")
                    Button(ProxyImportUX.text("Загрузить список")) { loadSubscription() }
                        .disabled(isFetchingSubscription || subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("profiles.loadSubscription")
                    TextField(ProxyImportUX.text("Название подписки (необязательно)"), text: $subscriptionTitle)
                        .accessibilityIdentifier("profiles.subscriptionTitle")
                    Button(ProxyImportUX.text("Сохранить ссылку для обновления")) { saveSubscription() }
                        .disabled(isFetchingSubscription || subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isFetchingSubscription { ProgressView() }
                    Text(refreshText("Загрузка по запросу или по выбранному интервалу на открытом экране импорта. Добавление — только после подтверждения. HTTP, HTTPS и SOCKS5.","Load on request or at the chosen interval while this import screen is open. Confirm before adding. HTTP, HTTPS and SOCKS5."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .disabled(automaticPreview != nil)
                if !savedSubscriptions.isEmpty {
                    Section(ProxyImportUX.text("Сохранённые подписки")) {
                        ForEach(savedSubscriptions) { item in
                            VStack(alignment:.leading,spacing:8) {
                                Button {loadSavedSubscription(item.id)} label: {
                                    VStack(alignment:.leading,spacing:4) {
                                        Text(item.title)
                                        Text(verbatim:item.providerHost).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.borderless).disabled(isFetchingSubscription || automaticPreview != nil)
                                Picker(refreshText("Автообновление","Auto refresh"),selection:Binding(get:{item.refresh?.interval ?? .manual},set:{configureRefresh(item.id,$0)})) {
                                    Text(refreshText("Вручную","Manual")).tag(SubscriptionRefreshSettings.Interval.manual)
                                    Text(refreshText("Каждый час","Hourly")).tag(SubscriptionRefreshSettings.Interval.hourly)
                                    Text(refreshText("Раз в день","Daily")).tag(SubscriptionRefreshSettings.Interval.daily)
                                    Text(refreshText("Раз в неделю","Weekly")).tag(SubscriptionRefreshSettings.Interval.weekly)
                                }.disabled(isFetchingSubscription)
                                if let policy=item.refresh {
                                    Text(refreshText("Тип для строк без протокола: ","Default protocol: ")+policy.defaultType.rawValue).font(.caption)
                                    if let last=item.lastAttempt {Text(refreshText("Отсчёт интервала: ","Interval starts: ")+last.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.secondary)}
                                }
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.compactMap { index in
                                savedSubscriptions.indices.contains(index) ? savedSubscriptions[index].id : nil
                            }
                            for id in ids { deleteSubscription(id) }
                        }
                    }
                }
                if let automaticPreview {
                    Section {
                        Text(refreshText("Обновлён список: ","Refreshed list: ")+automaticPreview.title)
                        Button(refreshText("Закрыть предпросмотр","Dismiss preview")){clearAutomaticPreview()}
                    }
                }
                if let message = importError {
                    Section {
                        Text(message).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        if cameraPermissionDenied, let settings = URL(string: UIApplication.openSettingsURLString) {
                            Button(ProxyImportUX.text("Открыть настройки камеры")) {
                                UIApplication.shared.open(settings)
                            }
                        }
                    }
                }
                if !preview.isEmpty {
                    Section(ProxyImportUX.text("Предпросмотр") + " (\(preview.count))") {
                        ForEach(preview.indices, id: \.self) { index in
                            let item = preview[index]
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text(verbatim: "\(item.type.rawValue) · \(item.host):\(item.port)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !pending.isEmpty {
                        Section {
                            Button(ProxyImportUX.text("Импортировать профили")) {
                                importProfiles()
                            }
                        }
                    }
                    if pending.count < preview.count {
                        Text(ProxyImportUX.text("Повторяющиеся и существующие профили будут пропущены"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if pending.isEmpty {
                        Text(ProxyImportUX.text("Все найденные профили уже добавлены"))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(ProxyImportUX.text("Новых профилей к добавлению:") + " \(pending.count)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(ProxyImportUX.text("Импорт прокси"))
            .keyboardDismissOnSwipeUp()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(ProxyImportUX.text("Закрыть")) { dismiss() } } }
            .onAppear {
                if !initialSource.isEmpty { source = initialSource; parse() }
                visible=true
                refreshSavedSubscriptions()
                refreshDueSubscription()
            }
            .task(id:scenePhase) {
                guard scenePhase == .active else{return}
                while !Task.isCancelled {
                    refreshDueSubscription()
                    do {try await Task.sleep(nanoseconds:60_000_000_000)}catch{return}
                }
            }
            .onChange(of:scenePhase){phase in if phase != .active {cancelSubscriptionFetch();clearAutomaticPreview()}}
            .onDisappear {visible=false;cancelSubscriptionFetch();clearAutomaticPreview()}
            .sheet(isPresented: $scanQR) {
                NavigationView {
                    ProxyQRScanner(onCode: { code in
                        scanQR = false
                        do {
                            // Shared APL QR links are also Apple deep links.
                            // Unwrap only our registered scheme; legacy proxy
                            // QR and multi-profile supplier codes keep working.
                            source = try ProxyProfileSharing.scannedSource(code)
                            parse()
                        } catch {
                            importError = ProxyImportUX.error(error)
                        }
                    }, onError: { failure in
                        scanQR = false
                        cameraPermissionDenied = failure.needsCameraSettings
                        importError = ProxyImportUX.text(failure.localizationKey)
                    }, onReady: { cameraReady = true })
                    .overlay(alignment: .bottom) {
                        Text(ProxyImportUX.text(cameraReady ? "Камера готова — наведите на QR-код" : "Запуск камеры..."))
                            .font(.footnote)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.bottom, 18)
                    }
                    .navigationTitle(ProxyImportUX.text("Сканирование QR"))
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button(ProxyImportUX.text("Отмена")) { scanQR = false }
                    } }
                }
            }
            .fileImporter(isPresented: $chooseFile,
                          allowedContentTypes: [.plainText, .commaSeparatedText, .xml, .json],
                          allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    source = try ProxyImportFileReader.readUTF8(from: url)
                    parse()
                } catch {
                    if !ProxyFilePickerCancellation.isUserCancellation(error) {
                        importError = ProxyImportUX.error(error)
                    }
                }
            }
        }
    }

    private func refreshText(_ ru:String,_ en:String)->String {AppL10n.effectiveLanguage == "ru" ? ru:en}
    private func configureRefresh(_ id:UUID,_ interval:SubscriptionRefreshSettings.Interval){
        do {
            try ProxySubscriptionStore().configureRefresh(id,interval:interval,defaultType:defaultType)
            if automaticPreview?.id==id {clearAutomaticPreview()}
            refreshSavedSubscriptions()
        }catch{importError=refreshText("Не удалось сохранить интервал обновления","Could not save refresh interval")}
    }
    private func cancelSubscriptionFetch(){
        refreshGeneration=UUID();subscriptionTask?.cancel();subscriptionTask=nil;isFetchingSubscription=false;activeSavedSource=nil
    }
    private func clearAutomaticPreview(){
        guard automaticPreview != nil else{return}
        automaticPreview=nil;parsedSource="";candidates=[]
    }
    private func refreshDueSubscription(){
        guard visible,scenePhase == .active,!isFetchingSubscription,!editorFocused,!scanQR,!chooseFile,
              source.isEmpty,subscriptionURL.isEmpty,subscriptionTitle.isEmpty,automaticPreview==nil else{return}
        do {
            let store=try ProxySubscriptionStore()
            guard let due=try store.list().filter({$0.refresh?.isDue(lastAttempt:$0.lastAttempt)==true}).min(by:{($0.lastAttempt ?? .distantPast)<($1.lastAttempt ?? .distantPast)}),
                  let claimed=try store.claimDue(due),claimed.refresh != nil else{return}
            refreshSavedSubscriptions()
            let url=try store.source(for:claimed.id)
            loadSubscription(savedURL:url,saved:claimed,automatic:true)
        }catch{importError=refreshText("Не удалось обновить подписку","Could not refresh subscription")}
    }
    private func refreshSavedSubscriptions() {
        do { savedSubscriptions = try ProxySubscriptionStore().list() }
        catch { importError = ProxyImportUX.text("Не удалось прочитать сохранённые подписки") }
    }

    private func saveSubscription() {
        do {
            try ProxySubscriptionStore().add(title: subscriptionTitle, urlText: subscriptionURL)
            subscriptionTitle = ""
            refreshSavedSubscriptions()
            importError = nil
        } catch {
            importError = ProxyImportUX.text("Не удалось безопасно сохранить подписку")
        }
    }

    private func deleteSubscription(_ id: UUID) {
        do {
            if activeSavedSource?.id==id {cancelSubscriptionFetch()}
            if automaticPreview?.id==id {clearAutomaticPreview()}
            try ProxySubscriptionStore().remove(id)
            refreshSavedSubscriptions()
        } catch {
            importError = ProxyImportUX.text("Не удалось удалить подписку")
        }
    }

    private func loadSavedSubscription(_ id: UUID) {
        guard visible,scenePhase == .active,!isFetchingSubscription,automaticPreview==nil else{return}
        do {
            let store=try ProxySubscriptionStore()
            guard let saved=try store.list().first(where:{$0.id==id}) else{return}
            let claimed=try store.markManualAttempt(saved)
            refreshSavedSubscriptions()
            let url=try store.source(for:id)
            loadSubscription(savedURL:url,saved:claimed)
        } catch {
            importError = ProxyImportUX.text("Не удалось прочитать сохранённую подписку")
        }
    }

    private func loadSubscription(savedURL: URL? = nil,saved:SavedProxySubscription?=nil,automatic:Bool=false) {
        guard visible,scenePhase == .active,!isFetchingSubscription,automaticPreview==nil else { return }
        let originalURL = subscriptionURL
        let originalSource = source
        let originalType = defaultType
        let selectedType = automatic ? (saved?.refresh?.defaultType ?? defaultType) : defaultType
        let url: URL
        do {
            url = try savedURL ?? ProxySubscriptionImport.sourceURL(originalURL)
        } catch {
            importError = ProxyImportUX.text("Нужна безопасная HTTPS-ссылка поставщика")
            return
        }
        editorFocused = false
        isFetchingSubscription = true
        activeSavedSource=saved
        let generation=UUID();refreshGeneration=generation
        importError = nil
        subscriptionTask = Task {
            defer {if refreshGeneration==generation {isFetchingSubscription=false;subscriptionTask=nil;activeSavedSource=nil}}
            do {
                let downloaded = try await ProxySubscriptionFetch.load(url, defaultType: selectedType)
                try Task.checkCancellation()
                // A concurrent user edit must not be overwritten by a delayed response.
                guard refreshGeneration==generation,visible,scenePhase == .active,!scanQR,!chooseFile,
                      subscriptionURL == originalURL, source == originalSource, defaultType == originalType else{return}
                if let saved {
                    guard try ProxySubscriptionStore().list().contains(saved) else{return}
                }
                if automatic,let saved {
                    // Do not display downloaded credentials in the editable input.
                    let rows=try ProxyImport.parse(downloaded,defaultType:selectedType)
                    var unique:[String:ImportedProxy]=[:]
                    for row in rows {
                        let key="\(row.type.rawValue)|\(row.host.lowercased())|\(row.port)|\(row.username)"
                        if let previous=unique[key],previous.password != row.password {throw ProxySubscriptionError.invalidBody}
                        unique[key]=row
                    }
                    candidates=rows;automaticPreview=saved;parsedSource=""
                } else {
                    source = downloaded
                    parse() // Preview only; the user must explicitly tap Import.
                }
            } catch is CancellationError {
                return
            } catch {
                guard refreshGeneration==generation,visible,scenePhase == .active else{return}
                // Never interpolate the URL, redirect target, native NSError
                // or supplier-supplied body into a public error message.
                if case ProxySubscriptionError.oversized = error {
                    importError = ProxyImportUX.text("Список поставщика слишком большой")
                } else if case ProxySubscriptionError.unsupportedBody = error {
                    importError = ProxyImportUX.text("Список содержит неподдерживаемые протоколы или формат")
                } else {
                    importError = ProxyImportUX.text("Не удалось безопасно загрузить список прокси")
                }
            }
        }
    }

    private func importProfiles() {
        guard visible,scenePhase == .active,!isFetchingSubscription else{return}
        editorFocused = false
        if let automaticPreview {
            guard (try? ProxySubscriptionStore().list().contains(automaticPreview))==true else{clearAutomaticPreview();return}
        }
        let items = pending
        guard !items.isEmpty else { return }
        // Importing into an existing installation must not unexpectedly
        // disconnect Auto or replace the user's manually selected server.
        // For a fresh install, only the first profile becomes the default.
        let noExistingProfiles = model.profiles.isEmpty
        var added: [UUID] = []
        for item in items {
            let before = Set(model.profiles.map(\.id))
            guard model.saveProfile(editingID: nil, name: item.name,
                                    host: item.host, portText: String(item.port),
                                    type: item.type, username: item.username,
                                    password: item.password, scanAfterSave: false,
                                    activateOnCreate: noExistingProfiles && added.isEmpty) else {
                let rolledBack = model.rollbackImportedProfiles(ids: Set(added))
                importError = rolledBack
                    ? ProxyImportUX.text("Не удалось сохранить профили. Изменения отменены")
                    : ProxyImportUX.text("Не удалось полностью отменить импорт. Проверьте список профилей")
                return
            }
            added += model.profiles.map(\.id).filter { !before.contains($0) }
        }
        // One bounded scan after the whole import, not up to 200 network
        // probe tasks and repeated connection attempts during the loop.
        Task { await model.scanProfiles() }
        dismiss()
    }

    private func parse() {
        editorFocused = false
        parsedSource = source
        parsedType = defaultType
        cameraPermissionDenied = false
        do { candidates = try ProxyImport.parse(source, defaultType: defaultType); importError = nil }
        catch { candidates = []; importError = ProxyImportUX.error(error) }
    }
}
