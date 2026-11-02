import SwiftUI

/// Scoped bulk operations: callers pass ONLY selected currently visible IDs.
/// Nothing in this view writes directly to ProfileStore or Keychain.
struct ProfileLibraryBulkActionsView: View {
    @ObservedObject var model: AppViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let visibleProfiles: [ProxyProfile]
    let selectedVisibleIDs: Set<UUID>
    let onSelectAll: () -> Void
    let onClearSelection: () -> Void
    let onDelete: () -> Void
    let onNewGroup: (Set<UUID>) -> Void

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 9) {
                selectionCount
                actionsMenu
                deleteButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                selectionCount
                Spacer()
                actionsMenu
                deleteButton
            }
        }
    }

    private var selectionCount: some View {
        Text(String(format: AppL10n.tr("Выбрано: %d"), selectedVisibleIDs.count))
            .font(.footnote)
            .foregroundStyle(Brand.softGray)
    }

    private var actionsMenu: some View {
        Menu {
            Button(AppL10n.tr("Выбрать все"), action: onSelectAll)
                .disabled(visibleProfiles.isEmpty)
            Button(AppL10n.tr("Снять выбор"), action: onClearSelection)
                .disabled(selectedVisibleIDs.isEmpty)
            Divider()
            Button(AppL10n.tr("В избранное")) {
                model.setFavorites(selectedVisibleIDs, enabled: true)
            }
            .disabled(selectedVisibleIDs.isEmpty)
            Button(AppL10n.tr("Убрать из избранного")) {
                model.setFavorites(selectedVisibleIDs, enabled: false)
            }
            .disabled(selectedVisibleIDs.isEmpty)
            ProfileLibraryGroupMenu(model: model, ids: selectedVisibleIDs,
                                    onNewGroup: onNewGroup)
            Button(AppL10n.tr("Проверить")) {
                Task { await model.scanProfiles(manual: true, specificIDs: selectedVisibleIDs) }
            }
            .disabled(selectedVisibleIDs.isEmpty ||
                      selectedVisibleIDs.count > 10 || model.isScanningProfiles)
        } label: {
            Label(AppL10n.tr("Действия"), systemImage: "ellipsis.circle")
                .frame(minHeight: 44)
        }
        .disabled(visibleProfiles.isEmpty)
        .accessibilityIdentifier("profiles.bulk.actions")
    }

    private var deleteButton: some View {
        Button(AppL10n.tr("Удалить"), role: .destructive, action: onDelete)
            .frame(minHeight: 44)
            .disabled(selectedVisibleIDs.isEmpty || model.vpn.isConnectedOrConnecting)
            .accessibilityHint(AppL10n.tr("Удаление требует отключить VPN"))
            .accessibilityIdentifier("profiles.bulk.delete")
    }
}
