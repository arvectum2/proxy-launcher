import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ProxyImportView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
    @State private var candidates: [ImportedProxy] = []
    @State private var importError: String?
    @State private var chooseFile = false
    @State private var scanQR = false
    var initialSource: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Ссылка или список прокси") {
                    TextEditor(text: $source).frame(minHeight: 110)
                        .onChange(of: source) { _ in candidates = []; importError = nil }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Вставить из буфера") {
                        source = UIPasteboard.general.string ?? ""
                        parse()
                    }
                    Button("Выбрать файл") { chooseFile = true }
                    Button("Сканировать QR-код") { scanQR = true }
                    Button("Проверить") { parse() }
                }
                if let message = importError { Section { Text(message).foregroundStyle(.red) } }
                if !candidates.isEmpty {
                    Section("Предпросмотр (\(candidates.count))") {
                        ForEach(candidates.indices, id: \.self) { index in
                            let item = candidates[index]
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text("\(item.type.rawValue) · \(item.host):\(item.port)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        Button("Импортировать профили") {
                            let pending = ProxyImport.withoutDuplicates(candidates, existing: model.profiles)
                            if pending.isEmpty { importError = "Все профили уже добавлены"; return }
                            var added: [UUID] = []
                            for item in pending {
                                let before = Set(model.profiles.map(\.id))
                                guard model.saveProfile(editingID: nil, name: item.name,
                                                        host: item.host, portText: String(item.port),
                                                        type: item.type, username: item.username,
                                                        password: item.password) else {
                                    for id in added { model.deleteProfile(id: id) }
                                    importError = "Не удалось сохранить профили. Изменения отменены"
                                    return
                                }
                                added += model.profiles.map(\.id).filter { !before.contains($0) }
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Импорт прокси")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onAppear { if !initialSource.isEmpty { source = initialSource; parse() } }
            .sheet(isPresented: $scanQR) {
                NavigationView {
                    ProxyQRScanner(onCode: { code in
                        scanQR = false
                        source = code
                        parse()
                    }, onError: { message in
                        scanQR = false
                        importError = message
                    })
                    .navigationTitle("Сканирование QR")
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { scanQR = false }
                    } }
                }
            }
            .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.plainText], allowsMultipleSelection: false) { result in
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
                } catch let caught { importError = caught.localizedDescription }
            }
        }
    }

    private func parse() {
        do { candidates = try ProxyImport.parse(source); importError = nil }
        catch let caught { candidates = []; importError = caught.localizedDescription }
    }
}
