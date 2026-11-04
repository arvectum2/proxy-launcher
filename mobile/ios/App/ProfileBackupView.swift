import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let aplBackup = UTType(exportedAs: "ru.arvectum.proxylauncher.aplbackup", conformingTo: .data)
}

/// FileDocument receives only AES-GCM ciphertext. No plaintext credentials
/// are written to a temporary document or shared using an unencrypted URL.
private struct EncryptedProfileBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.aplBackup] }
    let encryptedData: Data

    init(encryptedData: Data) { self.encryptedData = encryptedData }

    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents,
              bytes.count <= ProfileBackupCodec.maxFileBytes else {
            throw ProfileBackupError.invalidFile
        }
        encryptedData = bytes
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: encryptedData)
    }
}

struct ProfileBackupView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var exportPassword = ""
    @State private var exportConfirmation = ""
    @State private var importPassword = ""
    @State private var encryptedData: Data?
    @State private var backupDocument: EncryptedProfileBackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    // Show only the essential label by default; detailed
                    // backup/security explanations remain available on demand.
                    DisclosureGroup {
                        Text(AppL10n.tr("Копия содержит адреса прокси, логины, пароли, избранное и группы. Файл шифруется до сохранения. Без пароля восстановить его невозможно."))
                            .font(.footnote)
                        Text(AppL10n.tr("Ни пароль копии, ни её содержимое не передаются на сервер Arvectum."))
                            .font(.caption).foregroundStyle(.secondary)
                    } label: {
                        Label(AppL10n.tr("Зашифрованная резервная копия"), systemImage: "lock.doc")
                    }
                    .accessibilityIdentifier("backup.explanation")
                }

                Section(AppL10n.tr("Сохранить копию")) {
                    SecureField(AppL10n.tr("Пароль копии (от 12 символов)"), text: $exportPassword)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("backup.export.password")
                    SecureField(AppL10n.tr("Повторите пароль"), text: $exportConfirmation)
                        .textContentType(.newPassword)
                    Button {
                        createBackup()
                    } label: {
                        Label(AppL10n.tr("Создать зашифрованный файл"), systemImage: "lock.doc")
                    }
                    .disabled(model.profiles.isEmpty || exportPassword.count < 12 ||
                              exportPassword != exportConfirmation)
                    .accessibilityIdentifier("backup.export.create")
                }

                Section(AppL10n.tr("Восстановить профили")) {
                    Button {
                        errorMessage = nil
                        showImporter = true
                    } label: {
                        Label(AppL10n.tr("Выбрать файл .aplbackup"), systemImage: "doc.badge.arrow.up")
                    }
                    if encryptedData != nil {
                        Text(AppL10n.tr("Зашифрованный файл выбран"))
                            .font(.caption).foregroundStyle(.secondary)
                        SecureField(AppL10n.tr("Пароль резервной копии"), text: $importPassword)
                            .textContentType(.password)
                            .accessibilityIdentifier("backup.import.password")
                        Button {
                            restoreBackup()
                        } label: {
                            Label(AppL10n.tr("Добавить профили из копии"), systemImage: "square.and.arrow.down")
                        }
                        .disabled(importPassword.isEmpty || model.vpn.isConnectedOrConnecting)
                        .accessibilityIdentifier("backup.import.restore")
                    }
                    Text(AppL10n.tr("Существующие профили не перезаписываются. Совпадающие пропускаются. Перед восстановлением отключите VPN."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                if let successMessage {
                    Section { Text(successMessage).foregroundStyle(.green) }
                }
            }
            .navigationTitle(AppL10n.tr("Резервные копии"))
            .keyboardDismissOnSwipeUp()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppL10n.tr("Закрыть")) { dismiss() }
                }
            }
        }
        .fileExporter(isPresented: $showExporter,
                      document: backupDocument,
                      contentType: .aplBackup,
                      defaultFilename: "APL-Profiles-Encrypted") { result in
            exportPassword = ""
            exportConfirmation = ""
            backupDocument = nil
            switch result {
            case .success:
                successMessage = AppL10n.tr("Зашифрованная копия сохранена")
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.aplBackup, .json],
                      allowsMultipleSelection: false) { result in
            do {
                guard let file = try result.get().first else { return }
                let scoped = file.startAccessingSecurityScopedResource()
                defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                if let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber,
                   size.intValue > ProfileBackupCodec.maxFileBytes {
                    throw ProfileBackupError.invalidFile
                }
                let contents = try Data(contentsOf: file)
                guard contents.count <= ProfileBackupCodec.maxFileBytes else {
                    throw ProfileBackupError.invalidFile
                }
                encryptedData = contents
                importPassword = ""
                successMessage = nil
                errorMessage = nil
            } catch {
                encryptedData = nil
                importPassword = ""
                errorMessage = AppL10n.tr(error.localizedDescription)
            }
        }
        .onDisappear {
            exportPassword = ""
            exportConfirmation = ""
            importPassword = ""
            encryptedData = nil
            backupDocument = nil
        }
    }

    private func createBackup() {
        errorMessage = nil
        successMessage = nil
        do {
            guard exportPassword == exportConfirmation else { throw ProfileBackupError.weakPassword }
            let encrypted = try model.createEncryptedProfileBackup(password: exportPassword)
            backupDocument = EncryptedProfileBackupDocument(encryptedData: encrypted)
            showExporter = true
        } catch {
            errorMessage = AppL10n.tr(error.localizedDescription)
        }
    }

    private func restoreBackup() {
        guard let encryptedData else { return }
        errorMessage = nil
        successMessage = nil
        do {
            let count = try model.restoreEncryptedProfileBackup(data: encryptedData, password: importPassword)
            successMessage = String(format: AppL10n.tr("Добавлено профилей: %d"), count)
            self.encryptedData = nil
            importPassword = ""
        } catch {
            errorMessage = AppL10n.tr(error.localizedDescription)
            importPassword = ""
        }
    }
}
