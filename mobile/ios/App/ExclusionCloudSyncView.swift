import CloudKit
import SwiftUI

/// Manual-only private iCloud sync. Visible only when the App ID, container,
/// entitlement and two-device acceptance gates enable APL_CLOUDKIT_ENABLED.
struct ExclusionCloudSyncView: View {
    @ObservedObject var model: AppViewModel
    let onApplied: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var checked = false
    @State private var remoteAbsent = false
    @State private var remote: ManualExclusionSnapshot?
    @State private var record: CKRecord?
    @State private var localAtPreview: [String] = []
    @State private var difference: ManualExclusionChange?
    @State private var status: String?
    @State private var confirmUpload = false
    private let cloud = ExclusionCloudKitService()

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Только ручные домены. Пароли, профили и настройки VPN в iCloud не отправляются.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Проверить iCloud") { Task { await inspect() } }
                        .disabled(busy)
                    if busy { ProgressView() }
                }
                if checked {
                    Section("Предпросмотр") {
                        if remoteAbsent { Text("Удалённый список пуст.") }
                        if let difference {
                            Text("Добавить: \(difference.toAdd.count); удалить: \(difference.toRemove.count)")
                            ForEach(difference.toAdd, id: \.self) { Text("+ " + $0) }
                            ForEach(difference.toRemove, id: \.self) { Text("− " + $0) }
                            Button("Применить удалённый список") { Task { await apply() } }
                                .disabled(busy)
                        }
                        Button("Сохранить мои исключения в iCloud") { confirmUpload = true }
                            .disabled(busy)
                    }
                }
                if let status { Section { Text(status).font(.footnote) } }
            }
            .navigationTitle("Исключения · iCloud")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            } }
            .confirmationDialog("Заменить список в личной базе iCloud?",
                                isPresented: $confirmUpload, titleVisibility: .visible) {
                Button("Подтвердить загрузку") { Task { await upload() } }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Другие устройства не меняют VPN автоматически: загрузка списка требует отдельного подтверждения.")
            }
        }
    }

    @MainActor private func inspect() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            localAtPreview = try SiteExclusionPolicy.normalizeAll(model.manualExclusions)
            if let (snapshot, version) = try await cloud.previewRemote() {
                remote = snapshot
                record = version
                remoteAbsent = false
                difference = try ExclusionSyncContract.preview(local: localAtPreview, remote: snapshot)
            } else {
                remote = nil
                record = nil
                remoteAbsent = true
                difference = nil
            }
            checked = true
            status = nil
        } catch {
            checked = false
            status = "Не удалось прочитать iCloud. Проверьте Apple ID, подключение и разрешения."
        }
    }

    @MainActor private func apply() async {
        guard !busy, let remote,
              (try? SiteExclusionPolicy.normalizeAll(model.manualExclusions)) == localAtPreview else {
            status = "Локальные правила изменились — обновите предпросмотр."
            return
        }
        busy = true
        defer { busy = false }
        let accepted = await model.saveExclusions(remote.manualDomains, graph: model.smartGraph)
        if accepted {
            onApplied()
            localAtPreview = remote.manualDomains
            difference = try? ExclusionSyncContract.preview(local: localAtPreview, remote: remote)
            status = "Правила применены через проверку и восстановление VPN."
        } else {
            status = "Не удалось применить список; старые правила сохранены."
        }
    }

    @MainActor private func upload() async {
        guard checked, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await cloud.upload(manualDomains: model.manualExclusions, expectedRemote: record,
                                       observedRemoteWasAbsent: remoteAbsent)
            checked = false // Require a fresh preview/changeTag before another upload.
            status = "Список сохранён в личной базе iCloud. Для повторной загрузки обновите предпросмотр."
        } catch {
            checked = false
            status = "Удалённый список мог измениться. Повторите предпросмотр перед сохранением."
        }
    }
}
