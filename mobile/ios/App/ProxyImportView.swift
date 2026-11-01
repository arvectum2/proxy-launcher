import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ProxyImportView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
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
        parsedSource == source && parsedType == defaultType ? candidates : []
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
            .onAppear { if !initialSource.isEmpty { source = initialSource; parse() } }
            .sheet(isPresented: $scanQR) {
                NavigationView {
                    ProxyQRScanner(onCode: { code in
                        scanQR = false
                        source = code
                        parse()
                    }, onError: { message in
                        scanQR = false
                        cameraPermissionDenied = message == "Нет доступа к камере"
                        importError = ProxyImportUX.text(message)
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
                          allowedContentTypes: [.plainText, .commaSeparatedText, .xml],
                          allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 256_000, let text = String(data: data, encoding: .utf8) else {
                        throw ProxyImportError.tooLarge
                    }
                    source = text
                    parse()
                } catch let caught { importError = ProxyImportUX.error(caught) }
            }
        }
    }

    private func importProfiles() {
        editorFocused = false
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
